package com.example.video_subtitle_translator

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import java.io.RandomAccessFile
import java.nio.ByteOrder

/**
 * 영상에서 오디오 트랙을 디코드해 16-bit **mono** PCM WAV 파일을 만든다.
 * 폐기된 FFmpegKit(16KB 페이지 비호환)을 대체하는 플랫폼 네이티브 추출기.
 *
 * 샘플레이트는 소스 네이티브 레이트를 유지(리샘플 없음)하며 WAV 헤더에 기록한다.
 * 멀티채널은 단순 평균으로 mono 다운믹스한다.
 */
object AudioExtractor {
    private const val TIMEOUT_US = 10_000L
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * 백그라운드 스레드에서 추출하고 메인 스레드로 [result]를 회신한다.
     *
     * [startMs]/[endMs]가 주어지면 그 시간 구간만 추출한다(실시간 자막용). 둘 다 null이면
     * 전체를 추출한다.
     */
    fun extractWavAsync(
        videoPath: String,
        outPath: String,
        startMs: Int?,
        endMs: Int?,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val info = extract(videoPath, outPath, startMs, endMs)
                mainHandler.post { result.success(info) }
            } catch (e: Throwable) {
                mainHandler.post {
                    result.error("extract_failed", e.message ?: e.javaClass.simpleName, null)
                }
            }
        }.start()
    }

    private fun extract(
        videoPath: String,
        outPath: String,
        startMs: Int?,
        endMs: Int?
    ): Map<String, Any> {
        val extractor = MediaExtractor()
        var codec: MediaCodec? = null
        val raf = RandomAccessFile(outPath, "rw")
        try {
            raf.setLength(0)
            raf.write(ByteArray(44)) // WAV 헤더 자리(나중에 패치)

            extractor.setDataSource(videoPath)

            var trackIndex = -1
            var inputFormat: MediaFormat? = null
            for (i in 0 until extractor.trackCount) {
                val f = extractor.getTrackFormat(i)
                val mime = f.getString(MediaFormat.KEY_MIME) ?: continue
                if (mime.startsWith("audio/")) {
                    trackIndex = i
                    inputFormat = f
                    break
                }
            }
            if (trackIndex < 0 || inputFormat == null) {
                throw IllegalStateException("오디오 트랙 없음")
            }
            extractor.selectTrack(trackIndex)

            // 구간 추출: 시작 지점으로 시킹(가장 가까운 sync 샘플). 약간 앞 샘플에 안착할
            // 수 있으나 호출자가 윈도우 시작을 명목값으로 보정한다.
            if (startMs != null && startMs > 0) {
                extractor.seekTo(startMs * 1000L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
            }
            val endUs = if (endMs != null) endMs * 1000L else -1L

            val mime = inputFormat.getString(MediaFormat.KEY_MIME)!!
            codec = MediaCodec.createDecoderByType(mime).apply {
                configure(inputFormat, null, null, 0)
                start()
            }

            var sampleRate = inputFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
            var channelCount = inputFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
            var pcmEncoding = AudioFormat.ENCODING_PCM_16BIT

            val bufferInfo = MediaCodec.BufferInfo()
            var sawInputEOS = false
            var sawOutputEOS = false
            var totalPcmBytes = 0L

            while (!sawOutputEOS) {
                if (!sawInputEOS) {
                    val inIndex = codec.dequeueInputBuffer(TIMEOUT_US)
                    if (inIndex >= 0) {
                        val inBuf = codec.getInputBuffer(inIndex)!!
                        val sampleSize = extractor.readSampleData(inBuf, 0)
                        // 구간 끝(endUs)에 도달했거나 트랙이 끝나면 입력 종료.
                        val pastEnd = endUs >= 0L &&
                            extractor.sampleTime >= 0L &&
                            extractor.sampleTime >= endUs
                        if (sampleSize < 0 || pastEnd) {
                            codec.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            sawInputEOS = true
                        } else {
                            codec.queueInputBuffer(
                                inIndex, 0, sampleSize, extractor.sampleTime, 0
                            )
                            extractor.advance()
                        }
                    }
                }

                val outIndex = codec.dequeueOutputBuffer(bufferInfo, TIMEOUT_US)
                when {
                    outIndex >= 0 -> {
                        if (bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            sawOutputEOS = true
                        }
                        if (bufferInfo.size > 0) {
                            val outBuf = codec.getOutputBuffer(outIndex)!!
                            outBuf.position(bufferInfo.offset)
                            outBuf.limit(bufferInfo.offset + bufferInfo.size)
                            val mono = downmixToMono16(
                                outBuf, bufferInfo.size, channelCount, pcmEncoding
                            )
                            raf.write(mono)
                            totalPcmBytes += mono.size
                        }
                        codec.releaseOutputBuffer(outIndex, false)
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val of = codec.outputFormat
                        sampleRate = of.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        channelCount = of.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        if (of.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                            pcmEncoding = of.getInteger(MediaFormat.KEY_PCM_ENCODING)
                        }
                    }
                }
            }

            if (totalPcmBytes <= 0L) throw IllegalStateException("디코드된 오디오 없음")

            writeWavHeader(raf, sampleRate, 1, totalPcmBytes)

            val durationMs = (totalPcmBytes / 2.0 / sampleRate * 1000.0).toInt()
            return mapOf(
                "sampleRate" to sampleRate,
                "channels" to 1,
                "durationMs" to durationMs
            )
        } finally {
            try { codec?.stop() } catch (_: Throwable) {}
            try { codec?.release() } catch (_: Throwable) {}
            try { extractor.release() } catch (_: Throwable) {}
            try { raf.close() } catch (_: Throwable) {}
        }
    }

    /** 디코더 출력 PCM(16-bit 또는 float)을 mono 16-bit little-endian 바이트로 변환한다. */
    private fun downmixToMono16(
        buf: java.nio.ByteBuffer,
        size: Int,
        channels: Int,
        pcmEncoding: Int
    ): ByteArray {
        buf.order(ByteOrder.LITTLE_ENDIAN)
        val ch = if (channels <= 0) 1 else channels
        return if (pcmEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
            val fb = buf.asFloatBuffer()
            val frames = (size / 4) / ch
            val out = ByteArray(frames * 2)
            for (i in 0 until frames) {
                var sum = 0f
                for (c in 0 until ch) sum += fb.get(i * ch + c)
                var v = (sum / ch * 32767f).toInt()
                if (v > 32767) v = 32767 else if (v < -32768) v = -32768
                out[i * 2] = (v and 0xFF).toByte()
                out[i * 2 + 1] = ((v shr 8) and 0xFF).toByte()
            }
            out
        } else {
            val sb = buf.asShortBuffer()
            val frames = (size / 2) / ch
            val out = ByteArray(frames * 2)
            for (i in 0 until frames) {
                var sum = 0
                for (c in 0 until ch) sum += sb.get(i * ch + c).toInt()
                val v = sum / ch
                out[i * 2] = (v and 0xFF).toByte()
                out[i * 2 + 1] = ((v shr 8) and 0xFF).toByte()
            }
            out
        }
    }

    /** [raf]의 처음 44바이트에 표준 PCM WAV 헤더를 기록한다(파일 끝에서 호출). */
    private fun writeWavHeader(
        raf: RandomAccessFile,
        sampleRate: Int,
        channels: Int,
        dataSize: Long
    ) {
        val bitsPerSample = 16
        val byteRate = sampleRate * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val header = ByteArray(44)
        // RIFF
        header.ascii(0, "RIFF")
        header.u32le(4, 36 + dataSize)
        header.ascii(8, "WAVE")
        // fmt
        header.ascii(12, "fmt ")
        header.u32le(16, 16)
        header.u16le(20, 1) // PCM
        header.u16le(22, channels)
        header.u32le(24, sampleRate.toLong())
        header.u32le(28, byteRate.toLong())
        header.u16le(32, blockAlign)
        header.u16le(34, bitsPerSample)
        // data
        header.ascii(36, "data")
        header.u32le(40, dataSize)
        raf.seek(0)
        raf.write(header)
    }

    private fun ByteArray.ascii(o: Int, s: String) {
        for (i in s.indices) this[o + i] = s[i].code.toByte()
    }

    private fun ByteArray.u16le(o: Int, v: Int) {
        this[o] = (v and 0xFF).toByte()
        this[o + 1] = ((v shr 8) and 0xFF).toByte()
    }

    private fun ByteArray.u32le(o: Int, v: Long) {
        this[o] = (v and 0xFF).toByte()
        this[o + 1] = ((v shr 8) and 0xFF).toByte()
        this[o + 2] = ((v shr 16) and 0xFF).toByte()
        this[o + 3] = ((v shr 24) and 0xFF).toByte()
    }
}
