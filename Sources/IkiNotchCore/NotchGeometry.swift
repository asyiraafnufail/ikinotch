import CoreGraphics

public enum NotchDisplayState: Equatable {
    case collapsed
    case expanded
}

public struct NotchMetrics: Equatable {
    public let bodyWidth: CGFloat
    public let height: CGFloat
    public let topEarRadius: CGFloat
    public let bottomCornerRadius: CGFloat

    public var totalWidth: CGFloat {
        bodyWidth + (topEarRadius * 2)
    }

    public var size: CGSize {
        CGSize(width: totalWidth, height: height)
    }

    public init(bodyWidth: CGFloat, height: CGFloat, topEarRadius: CGFloat, bottomCornerRadius: CGFloat) {
        self.bodyWidth = bodyWidth
        self.height = height
        self.topEarRadius = topEarRadius
        self.bottomCornerRadius = bottomCornerRadius
    }
}

public enum NotchGeometry {
    public static let shadowHorizontalPadding: CGFloat = 20
    public static let shadowBottomPadding: CGFloat = 24

    public static func collapsedMetrics(
        preset: NotchSizePreset,
        customWidth: CGFloat,
        customHeight: CGFloat,
        menuBarHeight: CGFloat = 25
    ) -> NotchMetrics {
        let bodyWidth: CGFloat
        let height: CGFloat

        if preset == .custom {
            bodyWidth = min(max(customWidth, 120), 320)
            height = min(max(customHeight, 20), 46)
        } else {
            bodyWidth = preset.defaultBodyWidth
            height = max(20, menuBarHeight)
        }

        let earRadius = min(7, height * 0.28)
        let bottomRadius = min(9, height * 0.36)
        return NotchMetrics(
            bodyWidth: bodyWidth,
            height: height,
            topEarRadius: earRadius,
            bottomCornerRadius: bottomRadius
        )
    }

    public static func expandedMetrics(hasNowPlayingOrCalendar: Bool = true) -> NotchMetrics {
        NotchMetrics(
            bodyWidth: 550,
            height: hasNowPlayingOrCalendar ? 192 : 124,
            topEarRadius: 10,
            bottomCornerRadius: 22
        )
    }

    public static func metrics(
        for state: NotchDisplayState,
        preset: NotchSizePreset,
        customWidth: CGFloat,
        customHeight: CGFloat,
        menuBarHeight: CGFloat = 25,
        hasContentCards: Bool = true
    ) -> NotchMetrics {
        switch state {
        case .collapsed:
            return collapsedMetrics(
                preset: preset,
                customWidth: customWidth,
                customHeight: customHeight,
                menuBarHeight: menuBarHeight
            )
        case .expanded:
            return expandedMetrics(hasNowPlayingOrCalendar: hasContentCards)
        }
    }

    /// Computes the AppKit screen-space frame for the panel, anchored cleanly to the top edge of `screenFrame`.
    public static func panelFrame(
        for state: NotchDisplayState,
        screenFrame: CGRect,
        preset: NotchSizePreset,
        customWidth: CGFloat,
        customHeight: CGFloat,
        menuBarHeight: CGFloat = 25,
        horizontalOffset: CGFloat,
        useExpandedWindowBounds: Bool,
        hasContentCards: Bool = true
    ) -> CGRect {
        let targetState: NotchDisplayState = useExpandedWindowBounds ? .expanded : state
        let m = metrics(
            for: targetState,
            preset: preset,
            customWidth: customWidth,
            customHeight: customHeight,
            menuBarHeight: menuBarHeight,
            hasContentCards: hasContentCards
        )

        let windowWidth: CGFloat
        let windowHeight: CGFloat
        if useExpandedWindowBounds || state != .collapsed {
            windowWidth = m.totalWidth + (shadowHorizontalPadding * 2)
            windowHeight = m.height + shadowBottomPadding
        } else {
            // Tightly fitted to the collapsed notch to minimize WindowServer surface & click blocking
            windowWidth = m.totalWidth
            windowHeight = m.height
        }

        let desiredCenterX = screenFrame.midX + horizontalOffset
        let minCenterX = screenFrame.minX + (windowWidth / 2) + 8
        let maxCenterX = screenFrame.maxX - (windowWidth / 2) - 8
        let clampedCenterX: CGFloat
        if minCenterX <= maxCenterX {
            clampedCenterX = min(max(desiredCenterX, minCenterX), maxCenterX)
        } else {
            clampedCenterX = screenFrame.midX
        }

        let originX = (clampedCenterX - (windowWidth / 2)).rounded()
        let originY = (screenFrame.maxY - windowHeight).rounded()

        return CGRect(x: originX, y: originY, width: windowWidth, height: windowHeight)
    }

    /// Clamps a horizontal offset and applies snap-to-center within a small threshold.
    public static func snappedHorizontalOffset(
        _ proposed: CGFloat,
        screenWidth: CGFloat,
        collapsedTotalWidth: CGFloat,
        snapThreshold: CGFloat = 8
    ) -> CGFloat {
        let maxOffset = max(0, (screenWidth / 2) - (collapsedTotalWidth / 2) - 24)
        let clamped = min(max(proposed, -maxOffset), maxOffset)
        if abs(clamped) <= snapThreshold {
            return 0
        }
        return clamped
    }

    /// Converts an AppKit screen frame (bottom-left origin) to Quartz global coordinates (top-left origin).
    public static func quartzRect(for screenFrame: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: screenFrame.minX,
            y: primaryScreenHeight - screenFrame.maxY,
            width: screenFrame.width,
            height: screenFrame.height
        )
    }

    /// Returns true if a Quartz window frame covers the entire target screen (native or video fullscreen).
    public static func isWindowBoundsFullscreen(
        _ windowBounds: CGRect,
        onScreenQuartzRect screenRect: CGRect,
        tolerance: CGFloat = 4
    ) -> Bool {
        let coversWidth = windowBounds.width >= screenRect.width - tolerance
        let coversHeight = windowBounds.height >= screenRect.height - tolerance
        let alignedX = abs(windowBounds.minX - screenRect.minX) <= tolerance
        let alignedY = abs(windowBounds.minY - screenRect.minY) <= tolerance
        return coversWidth && coversHeight && alignedX && alignedY
    }
}
