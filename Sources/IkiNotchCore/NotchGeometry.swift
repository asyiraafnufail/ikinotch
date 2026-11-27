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
    public let topMargin: CGFloat

    public var totalWidth: CGFloat {
        bodyWidth + (topEarRadius * 2)
    }

    public var totalHeight: CGFloat {
        height + topMargin
    }

    public var size: CGSize {
        CGSize(width: totalWidth, height: totalHeight)
    }

    public init(
        bodyWidth: CGFloat,
        height: CGFloat,
        topEarRadius: CGFloat,
        bottomCornerRadius: CGFloat,
        topMargin: CGFloat = 0
    ) {
        self.bodyWidth = bodyWidth
        self.height = height
        self.topEarRadius = topEarRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.topMargin = topMargin
    }
}

public enum NotchGeometry {
    public static let shadowHorizontalPadding: CGFloat = 20
    public static let shadowBottomPadding: CGFloat = 24

    public static func collapsedMetrics(
        preset: NotchSizePreset,
        customWidth: CGFloat,
        customHeight: CGFloat,
        menuBarHeight: CGFloat = 25,
        shapeStyle: NotchShapeStyle = .notch
    ) -> NotchMetrics {
        let bodyWidth: CGFloat
        let baseHeight: CGFloat

        if preset == .custom {
            bodyWidth = min(max(customWidth, 120), 320)
            baseHeight = min(max(customHeight, 20), 46)
        } else {
            bodyWidth = preset.defaultBodyWidth
            baseHeight = max(20, menuBarHeight)
        }

        if shapeStyle == .pill {
            let pillHeight = max(18, baseHeight.rounded() - 5)
            return NotchMetrics(
                bodyWidth: bodyWidth.rounded(),
                height: pillHeight,
                topEarRadius: 0,
                bottomCornerRadius: pillHeight / 2,
                topMargin: 2
            )
        }

        let earRadius = min(7, baseHeight * 0.28)
        let bottomRadius = min(9, baseHeight * 0.36)
        return NotchMetrics(
            bodyWidth: bodyWidth,
            height: baseHeight,
            topEarRadius: earRadius,
            bottomCornerRadius: bottomRadius,
            topMargin: 0
        )
    }

    public static func expandedMetrics(
        hasNowPlayingOrCalendar: Bool = true,
        shapeStyle: NotchShapeStyle = .notch
    ) -> NotchMetrics {
        if shapeStyle == .pill {
            return NotchMetrics(
                bodyWidth: 550,
                height: hasNowPlayingOrCalendar ? 192 : 124,
                topEarRadius: 0,
                bottomCornerRadius: 24,
                topMargin: 2
            )
        }
        return NotchMetrics(
            bodyWidth: 550,
            height: hasNowPlayingOrCalendar ? 192 : 124,
            topEarRadius: 10,
            bottomCornerRadius: 22,
            topMargin: 0
        )
    }

    public static func metrics(
        for state: NotchDisplayState,
        preset: NotchSizePreset,
        customWidth: CGFloat,
        customHeight: CGFloat,
        menuBarHeight: CGFloat = 25,
        shapeStyle: NotchShapeStyle = .notch,
        hasContentCards: Bool = true
    ) -> NotchMetrics {
        switch state {
        case .collapsed:
            return collapsedMetrics(
                preset: preset,
                customWidth: customWidth,
                customHeight: customHeight,
                menuBarHeight: menuBarHeight,
                shapeStyle: shapeStyle
            )
        case .expanded:
            return expandedMetrics(
                hasNowPlayingOrCalendar: hasContentCards,
                shapeStyle: shapeStyle
            )
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
        shapeStyle: NotchShapeStyle = .notch,
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
            shapeStyle: shapeStyle,
            hasContentCards: hasContentCards
        )

        let windowWidth: CGFloat
        let windowHeight: CGFloat
        if useExpandedWindowBounds || state != .collapsed {
            windowWidth = (m.totalWidth + (shadowHorizontalPadding * 2)).rounded(.up)
            windowHeight = (m.totalHeight + shadowBottomPadding).rounded(.up)
        } else {
            // Tightly fitted to the collapsed notch/pill with integer height so maxY always equals screenFrame.maxY
            windowWidth = (m.totalWidth + (shapeStyle == .pill ? 4 : 0)).rounded(.up)
            windowHeight = (m.totalHeight + (shapeStyle == .pill ? 2 : 0)).rounded(.up)
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
        let originY = screenFrame.maxY - windowHeight

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
