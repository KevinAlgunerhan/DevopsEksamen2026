
package no.pgr301.exam.validation;

import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.multipart.MultipartFile;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayInputStream;
import java.io.IOException;

@Component
public class ImageValidator {

    private static final byte[] JPEG_SIGNATURE = {
            (byte) 0xFF, (byte) 0xD8, (byte) 0xFF
    };

    private static final byte[] PNG_SIGNATURE = {
            (byte) 0x89, 0x50, 0x4E, 0x47,
            0x0D, 0x0A, 0x1A, 0x0A
    };

    public byte[] validateAndRead(MultipartFile image) throws IOException {

        if (image == null || image.isEmpty()) {
            throw new IllegalArgumentException(
                    "Image file cannot be empty"
            );
        }

        String contentType = image.getContentType();

        if (!MediaType.IMAGE_JPEG_VALUE.equals(contentType)
                && !MediaType.IMAGE_PNG_VALUE.equals(contentType)) {
            throw new IllegalArgumentException(
                    "Only JPEG and PNG images are supported"
            );
        }

        byte[] bytes = image.getBytes();

        if (!hasValidSignature(bytes, contentType)) {
            throw new IllegalArgumentException(
                    "Image content does not match the declared file type"
            );
        }

        if (!isValidImage(bytes)) {
            throw new IllegalArgumentException(
                    "The uploaded file is not a valid image"
            );
        }

        return bytes;
    }

    private boolean hasValidSignature(byte[] bytes, String contentType) {

        if (MediaType.IMAGE_JPEG_VALUE.equals(contentType)) {
            return startsWith(bytes, JPEG_SIGNATURE);
        }

        if (MediaType.IMAGE_PNG_VALUE.equals(contentType)) {
            return startsWith(bytes, PNG_SIGNATURE);
        }

        return false;
    }

    
    private boolean isValidImage(byte[] bytes) {

        try (ByteArrayInputStream input = new ByteArrayInputStream(bytes)) {
            BufferedImage image = ImageIO.read(input);
            return image != null;
        } catch (IOException exception) {
            return false;
        }
    }


    private boolean startsWith(byte[] bytes, byte[] signature) {

        if (bytes.length < signature.length) {
            return false;
        }

        for (int i = 0; i < signature.length; i++) {
            if (bytes[i] != signature[i]) {
                return false;
            }
        }

        return true;
    }
}
