
package no.pgr301.exam.controller;

import no.pgr301.exam.model.AnalyzeResponse;
import no.pgr301.exam.service.WishlistService;
import no.pgr301.exam.validation.ImageValidator;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.web.servlet.MockMvc;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(AppController.class)
@Import(ImageValidator.class)
class AppControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @MockBean
    private WishlistService wishlistService;

    private AnalyzeResponse createResponse() {
        return new AnalyzeResponse(
                "test-image.jpg",
                List.of("Chair", "Table"),
                "A modern living room",
                "A person interested in interior design",
                List.of(),
                "2026-11-13T12:00:00Z"
        );
    }

    private byte[] createImageBytes(String format) throws IOException {
        BufferedImage image = new BufferedImage(
                1,
                1,
                BufferedImage.TYPE_INT_RGB
        );

        ByteArrayOutputStream output = new ByteArrayOutputStream();

        boolean written = ImageIO.write(image, format, output);

        if (!written) {
            throw new IOException("Could not create test image: " + format);
        }

        return output.toByteArray();
    }

    @Test
    void healthEndpointShouldReturnUp() throws Exception {
        mockMvc.perform(get("/api/health"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("UP"))
                .andExpect(jsonPath("$.timestamp").exists());
    }

    @Test
    void shouldAcceptValidJpegImage() throws Exception {
        MockMultipartFile image = new MockMultipartFile(
                "image",
                "test.jpg",
                MediaType.IMAGE_JPEG_VALUE,
                createImageBytes("jpeg")
        );

        when(wishlistService.process(
                any(byte[].class),
                eq("test.jpg"),
                eq(MediaType.IMAGE_JPEG_VALUE)
        )).thenReturn(createResponse());

        mockMvc.perform(multipart("/api/analyze").file(image))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.s3Key").value("test-image.jpg"));

        verify(wishlistService).process(
                any(byte[].class),
                eq("test.jpg"),
                eq(MediaType.IMAGE_JPEG_VALUE)
        );
    }

    @Test
    void shouldAcceptValidPngImage() throws Exception {
        MockMultipartFile image = new MockMultipartFile(
                "image",
                "test.png",
                MediaType.IMAGE_PNG_VALUE,
                createImageBytes("png")
        );

        when(wishlistService.process(
                any(byte[].class),
                eq("test.png"),
                eq(MediaType.IMAGE_PNG_VALUE)
        )).thenReturn(createResponse());

        mockMvc.perform(multipart("/api/analyze").file(image))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.s3Key").value("test-image.jpg"));

        verify(wishlistService).process(
                any(byte[].class),
                eq("test.png"),
                eq(MediaType.IMAGE_PNG_VALUE)
        );
    }

    @Test
    void shouldRejectEmptyImage() throws Exception {
        MockMultipartFile image = new MockMultipartFile(
                "image",
                "empty.jpg",
                MediaType.IMAGE_JPEG_VALUE,
                new byte[0]
        );

        mockMvc.perform(multipart("/api/analyze").file(image))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value(
                        "Image file cannot be empty"
                ));
    }

    @Test
    void shouldRejectUnsupportedImageFormat() throws Exception {
        MockMultipartFile image = new MockMultipartFile(
                "image",
                "test.gif",
                MediaType.IMAGE_GIF_VALUE,
                new byte[]{1, 2, 3}
        );

        mockMvc.perform(multipart("/api/analyze").file(image))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value(
                        "Only JPEG and PNG images are supported"
                ));
    }

    @Test
    void shouldRejectJpegWithInvalidSignature() throws Exception {
        MockMultipartFile image = new MockMultipartFile(
                "image",
                "fake.jpg",
                MediaType.IMAGE_JPEG_VALUE,
                new byte[]{1, 2, 3, 4}
        );

        mockMvc.perform(multipart("/api/analyze").file(image))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value(
                        "Image content does not match the declared file type"
                ));
    }

    @Test
    void shouldRejectImageWithValidSignatureButInvalidContent() throws Exception {
        byte[] invalidJpeg = {
                (byte) 0xFF,
                (byte) 0xD8,
                (byte) 0xFF,
                0x01,
                0x02,
                0x03
        };

        MockMultipartFile image = new MockMultipartFile(
                "image",
                "invalid.jpg",
                MediaType.IMAGE_JPEG_VALUE,
                invalidJpeg
        );

        mockMvc.perform(multipart("/api/analyze").file(image))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value(
                        "The uploaded file is not a valid image"
                ));
    }
}
