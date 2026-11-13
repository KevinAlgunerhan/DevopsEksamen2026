
package no.pgr301.exam.service;

import no.pgr301.exam.model.AnalyzeResponse;
import no.pgr301.exam.model.GiftAnalysis;
import no.pgr301.exam.model.GiftSuggestion;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.util.List;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class WishlistServiceTest {

    private S3Service s3;
    private RekognitionService rekognition;
    private BedrockService bedrock;
    private WishlistService wishlistService;

    @BeforeEach
    void setUp() {
        s3 = mock(S3Service.class);
        rekognition = mock(RekognitionService.class);
        bedrock = mock(BedrockService.class);

        wishlistService = new WishlistService(s3, rekognition, bedrock);
    }

    @Test
    void processShouldUploadImageAnalyzeLabelsAndGenerateSuggestions() {
        byte[] imageBytes = new byte[]{1, 2, 3};
        String filename = "living-room.jpg";
        String contentType = "image/jpeg";
        String s3Key = "uploads/living-room.jpg";

        List<String> labels = List.of("Sofa", "Table", "Lamp");

        GiftSuggestion suggestion = mock(GiftSuggestion.class);
        List<GiftSuggestion> suggestions = List.of(suggestion);

        GiftAnalysis giftAnalysis = new GiftAnalysis(
                "A modern living room",
                "An adult who enjoys interior design",
                suggestions
        );

        when(s3.upload(imageBytes, filename, contentType)).thenReturn(s3Key);
        when(rekognition.detectLabels(imageBytes)).thenReturn(labels);
        when(bedrock.suggestGifts(labels)).thenReturn(giftAnalysis);

        AnalyzeResponse response = wishlistService.process(
                imageBytes, filename, contentType
        );

        assertNotNull(response);
        assertEquals(s3Key, response.s3Key());
        assertEquals(labels, response.labels());
        assertEquals("A modern living room", response.roomAnalysis());
        assertEquals("An adult who enjoys interior design", response.recipientProfile());
        assertEquals(suggestions, response.suggestions());
        assertNotNull(response.timestamp());

        verify(s3).upload(imageBytes, filename, contentType);
        verify(rekognition).detectLabels(imageBytes);
        verify(bedrock).suggestGifts(labels);
        verifyNoMoreInteractions(s3, rekognition, bedrock);
    }

    @Test
    void processShouldStopWhenS3UploadFails() {
        byte[] imageBytes = new byte[]{1, 2, 3};

        when(s3.upload(imageBytes, "image.jpg", "image/jpeg"))
                .thenThrow(new RuntimeException("S3 upload failed"));

        RuntimeException exception = assertThrows(
                RuntimeException.class,
                () -> wishlistService.process(
                        imageBytes, "image.jpg", "image/jpeg"
                )
        );

        assertEquals("S3 upload failed", exception.getMessage());

        verify(s3).upload(imageBytes, "image.jpg", "image/jpeg");
        verifyNoInteractions(rekognition, bedrock);
    }

    @Test
    void processShouldStopWhenRekognitionFails() {
        byte[] imageBytes = new byte[]{1, 2, 3};

        when(s3.upload(imageBytes, "image.jpg", "image/jpeg"))
                .thenReturn("uploads/image.jpg");

        when(rekognition.detectLabels(imageBytes))
                .thenThrow(new RuntimeException("Rekognition failed"));

        RuntimeException exception = assertThrows(
                RuntimeException.class,
                () -> wishlistService.process(
                        imageBytes, "image.jpg", "image/jpeg"
                )
        );

        assertEquals("Rekognition failed", exception.getMessage());

        verify(s3).upload(imageBytes, "image.jpg", "image/jpeg");
        verify(rekognition).detectLabels(imageBytes);
        verifyNoInteractions(bedrock);
    }

    @Test
    void processShouldPropagateBedrockFailure() {
        byte[] imageBytes = new byte[]{1, 2, 3};
        List<String> labels = List.of("Sofa", "Lamp");

        when(s3.upload(imageBytes, "image.jpg", "image/jpeg"))
                .thenReturn("uploads/image.jpg");

        when(rekognition.detectLabels(imageBytes))
                .thenReturn(labels);

        when(bedrock.suggestGifts(labels))
                .thenThrow(new RuntimeException("Bedrock generation failed"));

        RuntimeException exception = assertThrows(
                RuntimeException.class,
                () -> wishlistService.process(
                        imageBytes, "image.jpg", "image/jpeg"
                )
        );

        assertEquals("Bedrock generation failed", exception.getMessage());

        verify(s3).upload(imageBytes, "image.jpg", "image/jpeg");
        verify(rekognition).detectLabels(imageBytes);
        verify(bedrock).suggestGifts(labels);
        verifyNoMoreInteractions(s3, rekognition, bedrock);
    }
}
