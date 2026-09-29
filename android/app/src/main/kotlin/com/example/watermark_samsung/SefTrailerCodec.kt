package com.example.watermark_samsung

import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile

/** 动态照片字节级编解码：Samsung SEF/SEFT 结构解析与构建、MP4 头校验、XMP APP1 注入 */
object SefTrailerCodec {
    private const val TAG = "UltraHDR"

    fun parseSamsungSefNative(bytes: ByteArray): Pair<Int, Int>? {
        val len = bytes.size
        if (len < 40) return null
        if (bytes[len - 4] != 0x53.toByte() || bytes[len - 3] != 0x45.toByte() ||
            bytes[len - 2] != 0x46.toByte() || bytes[len - 1] != 0x54.toByte()
        ) {
            return null
        }

        try {
            val sefDataSize = (bytes[len - 8].toInt() and 0xFF) or
                    ((bytes[len - 7].toInt() and 0xFF) shl 8) or
                    ((bytes[len - 6].toInt() and 0xFF) shl 16) or
                    ((bytes[len - 5].toInt() and 0xFF) shl 24)
            if (sefDataSize <= 0 || sefDataSize > 65536) return null
            val sefhAbs = len - 8 - sefDataSize
            if (sefhAbs < 0 || sefhAbs + 12 > len) return null

            if (bytes[sefhAbs] != 0x53.toByte() || bytes[sefhAbs + 1] != 0x45.toByte() ||
                bytes[sefhAbs + 2] != 0x46.toByte() || bytes[sefhAbs + 3] != 0x48.toByte()
            ) {
                return null
            }

            val count = (bytes[sefhAbs + 8].toInt() and 0xFF) or
                    ((bytes[sefhAbs + 9].toInt() and 0xFF) shl 8) or
                    ((bytes[sefhAbs + 10].toInt() and 0xFF) shl 16) or
                    ((bytes[sefhAbs + 11].toInt() and 0xFF) shl 24)
            val entryCount = count.coerceIn(1, 32)

            val entries = mutableListOf<Pair<Int, Int>>() // (negOffset, entryOffset)
            for (i in 0 until entryCount) {
                val entryOffset = sefhAbs + 12 + (i * 12)
                if (entryOffset + 12 > len) break

                val negativeOffset = (bytes[entryOffset + 4].toInt() and 0xFF) or
                        ((bytes[entryOffset + 5].toInt() and 0xFF) shl 8) or
                        ((bytes[entryOffset + 6].toInt() and 0xFF) shl 16) or
                        ((bytes[entryOffset + 7].toInt() and 0xFF) shl 24)

                if (negativeOffset in 1..sefhAbs) {
                    entries.add(Pair(negativeOffset, entryOffset))
                }
            }

            for (entry in entries) {
                val negativeOffset = entry.first
                val fieldStart = sefhAbs - negativeOffset
                val mp4Start = fieldStart + 24

                if (mp4Start >= 0 && mp4Start + 8 <= len) {
                    if (bytes[mp4Start + 4] == 0x66.toByte() && bytes[mp4Start + 5] == 0x74.toByte() &&
                        bytes[mp4Start + 6] == 0x79.toByte() && bytes[mp4Start + 7] == 0x70.toByte()
                    ) {
                        // 找到下一个较小 negativeOffset 的 entry (即物理上紧随其后的字段)，计算精确结尾
                        val nextSmallerNeg = entries.map { it.first }.filter { it < negativeOffset }.maxOrNull() ?: 0
                        val videoEnd = if (nextSmallerNeg > 0) sefhAbs - nextSmallerNeg else sefhAbs
                        return Pair(mp4Start, videoEnd)
                    }
                }
            }
        } catch (_: Exception) {}
        return null
    }

    fun isValidMp4HeaderNative(bytes: ByteArray, offset: Int): Boolean {
        if (offset < 0 || offset + 16 > bytes.size) return false
        if (bytes[offset + 4] != 0x66.toByte() ||
            bytes[offset + 5] != 0x74.toByte() ||
            bytes[offset + 6] != 0x79.toByte() ||
            bytes[offset + 7] != 0x70.toByte()
        ) {
            return false
        }

        val b0 = bytes[offset + 8]
        val b1 = bytes[offset + 9]
        val b2 = bytes[offset + 10]
        val b3 = bytes[offset + 11]
        val brand = String(byteArrayOf(b0, b1, b2, b3), Charsets.US_ASCII).lowercase()

        val staticImageBrands = setOf("heic", "heix", "heim", "heis", "mif1", "msf1", "avif", "avis", "avic", "miaf")
        if (staticImageBrands.contains(brand)) {
            return false
        }

        val validVideoBrands = setOf(
            "mp41", "mp42", "isom", "iso2", "iso4", "iso5", "iso6",
            "avc1", "hvc1", "hev1", "qt  ", "m4v ", "m4a ", "msnv",
            "dash", "mp71", "3gp4", "3gp5", "3gp6", "3g2a", "caep",
            "qvfs", "f4v ", "sec ", "s264", "kddi", "mmp4"
        )
        if (validVideoBrands.contains(brand) || brand.startsWith("mp4") || brand.startsWith("iso") || brand.startsWith("3gp")) {
            return true
        }

        val boxSize = ((bytes[offset].toInt() and 0xFF) shl 24) or
                ((bytes[offset + 1].toInt() and 0xFF) shl 16) or
                ((bytes[offset + 2].toInt() and 0xFF) shl 8) or
                (bytes[offset + 3].toInt() and 0xFF)
        if (boxSize in 16..65536) {
            val compatEnd = Math.min(offset + boxSize, bytes.size)
            var c = offset + 16
            while (c + 4 <= compatEnd) {
                val cBrand = String(byteArrayOf(bytes[c], bytes[c + 1], bytes[c + 2], bytes[c + 3]), Charsets.US_ASCII).lowercase()
                if (validVideoBrands.contains(cBrand) || cBrand.startsWith("mp4") || cBrand.startsWith("iso") || cBrand.startsWith("3gp")) {
                    return true
                }
                c += 4
            }
        }
        return false
    }

    fun nativeCompositeMotionPhoto(
        watermarkedJpgBytes: ByteArray,
        motionVideoBytes: ByteArray,
        timestampUs: Long
    ): ByteArray {
        val videoLength = motionVideoBytes.size
        val sefBlockSize = 32
        val microVideoOffset = videoLength + sefBlockSize

        val effectiveTimestampUs = if (timestampUs > 0L) timestampUs else 1500000L

        // 1. 构建 Samsung SEF 尾部结构
        val sefTrailer = ByteArrayOutputStream(24 + videoLength + 32)
        // Part 1: Field Header (24 bytes)
        sefTrailer.write(byteArrayOf(0x00, 0x00, 0x30, 0x0A))
        sefTrailer.write(byteArrayOf(0x10, 0x00, 0x00, 0x00)) // 16 LE
        sefTrailer.write("MotionPhoto_Data".toByteArray(Charsets.US_ASCII))

        // Part 2: Video Bytes
        sefTrailer.write(motionVideoBytes)

        // Part 3: SEFH Index Block (32 bytes)
        val negativeOffset = 24 + videoLength
        val dataLength = 24 + videoLength
        sefTrailer.write("SEFH".toByteArray(Charsets.US_ASCII))
        sefTrailer.write(byteArrayOf(0x6A, 0x00, 0x00, 0x00)) // version 106 LE
        sefTrailer.write(byteArrayOf(0x01, 0x00, 0x00, 0x00)) // count 1 LE
        sefTrailer.write(byteArrayOf(0x00, 0x00, 0x30, 0x0A)) // entry marker
        sefTrailer.write(byteArrayOf(
            (negativeOffset and 0xFF).toByte(),
            ((negativeOffset shr 8) and 0xFF).toByte(),
            ((negativeOffset shr 16) and 0xFF).toByte(),
            ((negativeOffset shr 24) and 0xFF).toByte()
        ))
        sefTrailer.write(byteArrayOf(
            (dataLength and 0xFF).toByte(),
            ((dataLength shr 8) and 0xFF).toByte(),
            ((dataLength shr 16) and 0xFF).toByte(),
            ((dataLength shr 24) and 0xFF).toByte()
        ))
        sefTrailer.write(byteArrayOf(0x18, 0x00, 0x00, 0x00)) // sefDataSize = 24 LE
        sefTrailer.write("SEFT".toByteArray(Charsets.US_ASCII))

        val sefTrailerBytes = sefTrailer.toByteArray()

        // 2. 构建 XMP (Google GCamera + GContainer + Samsung 双格式)
        val xmpString = """<x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 5.1.0-jc003">
  <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
    <rdf:Description rdf:about=""
        xmlns:GCamera="http://ns.google.com/photos/1.0/camera/"
        xmlns:Container="http://ns.google.com/photos/1.0/container/"
        xmlns:Item="http://ns.google.com/photos/1.0/container/item/"
        xmlns:Camera="http://ns.google.com/photos/1.0/camera/"
        xmlns:samsung="http://ns.samsung.com/photo/1.0/"
        GCamera:MotionPhoto="1"
        GCamera:MotionPhotoVersion="1"
        GCamera:MotionPhotoPresentationTimestampUs="$effectiveTimestampUs"
        GCamera:MicroVideo="1"
        GCamera:MicroVideoVersion="1"
        GCamera:MicroVideoOffset="$microVideoOffset"
        GCamera:MicroVideoPresentationTimestampUs="$effectiveTimestampUs"
        Camera:MotionPhoto="1"
        Camera:MicroVideo="1"
        Camera:MicroVideoOffset="$microVideoOffset"
        samsung:MotionPhoto="1"
        samsung:MotionPhotoVersion="1"
        samsung:MotionPhoto_Data="1"
        samsung:SEFType="2048"
        samsung:SpecialType="2048">
      <Container:Directory>
        <rdf:Seq>
          <rdf:li rdf:parseType="Resource">
            <Item:Mime>image/jpeg</Item:Mime>
            <Item:Semantic>Primary</Item:Semantic>
            <Item:Length>0</Item:Length>
            <Item:Padding>24</Item:Padding>
          </rdf:li>
          <rdf:li rdf:parseType="Resource">
            <Item:Mime>video/mp4</Item:Mime>
            <Item:Semantic>MotionPhoto</Item:Semantic>
            <Item:Length>$videoLength</Item:Length>
            <Item:Padding>$sefBlockSize</Item:Padding>
          </rdf:li>
        </rdf:Seq>
      </Container:Directory>
    </rdf:Description>
  </rdf:RDF>
</x:xmpmeta>
"""
        val xmpBytes = xmpString.toByteArray(Charsets.UTF_8)

        // 3. 将 XMP APP1 注入 JPEG
        val jpgWithXmp = injectXmpApp1Native(watermarkedJpgBytes, xmpBytes)

        // 4. 拼接 JPEG 与 SEF Trailer
        val result = ByteArray(jpgWithXmp.size + sefTrailerBytes.size)
        System.arraycopy(jpgWithXmp, 0, result, 0, jpgWithXmp.size)
        System.arraycopy(sefTrailerBytes, 0, result, jpgWithXmp.size, sefTrailerBytes.size)

        return result
    }

    fun injectXmpApp1Native(jpgBytes: ByteArray, xmpBytes: ByteArray): ByteArray {
        if (jpgBytes.size < 4 || jpgBytes[0] != 0xFF.toByte() || jpgBytes[1] != 0xD8.toByte()) {
            return jpgBytes
        }

        val nsBytes = "http://ns.adobe.com/xap/1.0/\u0000".toByteArray(Charsets.UTF_8)
        val markerLen = nsBytes.size + xmpBytes.size + 2
        val app1Seg = ByteArrayOutputStream(4 + nsBytes.size + xmpBytes.size)
        app1Seg.write(0xFF)
        app1Seg.write(0xE1)
        app1Seg.write((markerLen shr 8) and 0xFF)
        app1Seg.write(markerLen and 0xFF)
        app1Seg.write(nsBytes)
        app1Seg.write(xmpBytes)
        val newApp1 = app1Seg.toByteArray()

        val out = ByteArrayOutputStream(jpgBytes.size + newApp1.size)
        out.write(0xFF)
        out.write(0xD8)

        var offset = 2
        var insertPos = 2

        while (offset + 4 < jpgBytes.size) {
            if (jpgBytes[offset] != 0xFF.toByte()) break
            val marker = jpgBytes[offset + 1].toInt() and 0xFF
            if (marker == 0xDA || marker == 0xD9) break
            val len = ((jpgBytes[offset + 2].toInt() and 0xFF) shl 8) or (jpgBytes[offset + 3].toInt() and 0xFF)
            val segEnd = offset + 2 + len
            if (marker == 0xE0 || (marker == 0xE1 && !isXmpSegmentNative(jpgBytes, offset, nsBytes))) {
                insertPos = segEnd
            }
            offset = segEnd
        }

        offset = 2
        var xmpWritten = false
        while (offset + 4 < jpgBytes.size) {
            if (jpgBytes[offset] != 0xFF.toByte()) {
                out.write(jpgBytes, offset, jpgBytes.size - offset)
                break
            }
            val marker = jpgBytes[offset + 1].toInt() and 0xFF
            if (marker == 0xDA || marker == 0xD9) {
                if (!xmpWritten) {
                    out.write(newApp1)
                    xmpWritten = true
                }
                out.write(jpgBytes, offset, jpgBytes.size - offset)
                break
            }
            val len = ((jpgBytes[offset + 2].toInt() and 0xFF) shl 8) or (jpgBytes[offset + 3].toInt() and 0xFF)
            val segEnd = offset + 2 + len

            if (marker == 0xE1 && isXmpSegmentNative(jpgBytes, offset, nsBytes)) {
                // 跳过旧 XMP 段
                offset = segEnd
                continue
            }

            out.write(jpgBytes, offset, segEnd - offset)
            if (!xmpWritten && segEnd >= insertPos) {
                out.write(newApp1)
                xmpWritten = true
            }
            offset = segEnd
        }

        if (!xmpWritten) {
            out.write(newApp1)
        }

        return out.toByteArray()
    }

    private fun isXmpSegmentNative(bytes: ByteArray, offset: Int, nsBytes: ByteArray): Boolean {
        if (offset + 4 + nsBytes.size > bytes.size) return false
        for (i in nsBytes.indices) {
            if (bytes[offset + 4 + i] != nsBytes[i]) return false
        }
        return true
    }

    /** 快速检测文件是否为动态照片 (Motion Photo / MicroVideo / SEF) */
    fun checkIsMotionPhotoFile(path: String): Boolean {
        try {
            val file = File(path)
            if (!file.exists()) return false
            val length = file.length()
            if (length < 2048) return false

            RandomAccessFile(file, "r").use { raf ->
                // 1. 检查文件尾部 8KB 是否包含三星 SEFT 结构且含有 MotionPhoto_Data 标记
                val tailSize = if (length > 8192) 8192 else length.toInt()
                raf.seek(length - tailSize)
                val tailBytes = ByteArray(tailSize)
                raf.readFully(tailBytes)

                if (tailSize >= 4 &&
                    tailBytes[tailSize - 4] == 0x53.toByte() && // S
                    tailBytes[tailSize - 3] == 0x45.toByte() && // E
                    tailBytes[tailSize - 2] == 0x46.toByte() && // F
                    tailBytes[tailSize - 1] == 0x54.toByte()    // T
                ) {
                    val tailStr = String(tailBytes, Charsets.ISO_8859_1)
                    if (tailStr.contains("MotionPhoto_Data")) {
                        return true
                    }
                }

                // 2. 检查头部 512KB 是否包含 Google / 小米 / OPPO / vivo / 三星 XMP 动态照片标签
                val headSize = if (length > 524288) 524288 else length.toInt()
                raf.seek(0)
                val headBytes = ByteArray(headSize)
                raf.readFully(headBytes)

                val headStr = String(headBytes, Charsets.ISO_8859_1)
                if (headStr.contains("MotionPhoto=\"1\"") ||
                    headStr.contains("MotionPhoto='1'") ||
                    headStr.contains("MicroVideo=\"1\"") ||
                    headStr.contains("MicroVideo='1'") ||
                    headStr.contains("MicroVideoOffset") ||
                    headStr.contains("Item:Semantic=\"MotionPhoto\"") ||
                    headStr.contains("samsung:MotionPhoto=\"1\"")
                ) {
                    return true
                }
            }
        } catch (_: Exception) {}
        return false
    }
}
