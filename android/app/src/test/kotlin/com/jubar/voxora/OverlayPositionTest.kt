package com.jubar.voxora

import org.junit.Assert.assertEquals
import org.junit.Test

class OverlayPositionTest {
    @Test
    fun `moves a saved landscape position back onto a portrait display`() {
        val result = clampOverlayPosition(
            position = OverlayPosition(x = 2200, y = 900),
            overlayWidth = 58,
            overlayHeight = 58,
            displayWidth = 1080,
            displayHeight = 2400,
        )

        assertEquals(OverlayPosition(x = 1022, y = 900), result)
    }

    @Test
    fun `keeps an already visible position unchanged`() {
        val result = clampOverlayPosition(
            position = OverlayPosition(x = 240, y = 480),
            overlayWidth = 58,
            overlayHeight = 58,
            displayWidth = 1080,
            displayHeight = 2400,
        )

        assertEquals(OverlayPosition(x = 240, y = 480), result)
    }

    @Test
    fun `recovers negative saved coordinates`() {
        val result = clampOverlayPosition(
            position = OverlayPosition(x = -120, y = -40),
            overlayWidth = 58,
            overlayHeight = 58,
            displayWidth = 1080,
            displayHeight = 2400,
        )

        assertEquals(OverlayPosition(x = 0, y = 0), result)
    }
}
