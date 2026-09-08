import Foundation

struct DesignColor: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let opacity: Double
    let lightRed: Double?
    let lightGreen: Double?
    let lightBlue: Double?
    let lightOpacity: Double?

    init(red: Int, green: Int, blue: Int, opacity: Double = 1) {
        self.red = Double(red) / 255
        self.green = Double(green) / 255
        self.blue = Double(blue) / 255
        self.opacity = opacity
        lightRed = nil
        lightGreen = nil
        lightBlue = nil
        lightOpacity = nil
    }

    init(
        lightRed: Int,
        lightGreen: Int,
        lightBlue: Int,
        lightOpacity: Double = 1,
        darkRed: Int,
        darkGreen: Int,
        darkBlue: Int,
        darkOpacity: Double = 1
    ) {
        red = Double(darkRed) / 255
        green = Double(darkGreen) / 255
        blue = Double(darkBlue) / 255
        opacity = darkOpacity
        self.lightRed = Double(lightRed) / 255
        self.lightGreen = Double(lightGreen) / 255
        self.lightBlue = Double(lightBlue) / 255
        self.lightOpacity = lightOpacity
    }
}

struct DesignConstants: Equatable, Sendable {
    struct Palette: Equatable, Sendable {
        let background: DesignColor
        let surface: DesignColor
        let surfaceLowest: DesignColor
        let surfaceHigh: DesignColor
        let primary: DesignColor
        let onPrimary: DesignColor
        let focus: DesignColor
        let secondary: DesignColor
        let tertiary: DesignColor
        let text: DesignColor
        let mutedText: DesignColor
        let outline: DesignColor
        let modalShadow: DesignColor
    }

    struct Typography: Equatable, Sendable {
        let displayFamily: String
        let bodyFamily: String
        let labelFamily: String
        let largeDisplaySize: Double
        let mobileDisplaySize: Double
        let headlineSize: Double
        let largeBodySize: Double
        let bodySize: Double
        let labelSize: Double
    }

    struct Spacing: Equatable, Sendable {
        let extraSmall: Double
        let base: Double
        let small: Double
        let medium: Double
        let large: Double
        let extraLarge: Double
        let gutter: Double
        let phoneMargin: Double
        let largeLayoutMargin: Double
    }

    struct Shape: Equatable, Sendable {
        let smallRadius: Double
        let standardRadius: Double
        let mediumRadius: Double
        let largeRadius: Double
        let extraLargeRadius: Double
        let capsuleRadius: Double
        let borderWidth: Double
        let focusOutlineWidth: Double
    }

    struct Shadow: Equatable, Sendable {
        let modalBlurRadius: Double
        let modalOpacity: Double
        let innerHighlightWidth: Double
    }

    struct Layout: Equatable, Sendable {
        let phonePortraitColumns: Int
        let largeLayoutColumns: Int
        let minimumSupportedWidth: Double
        let phoneReferenceWidth: Double
        let tabletReferenceWidth: Double
    }

    let palette: Palette
    let typography: Typography
    let spacing: Spacing
    let shape: Shape
    let shadow: Shadow
    let layout: Layout

    static let standard = DesignConstants(
        palette: Palette(
            background: DesignColor(lightRed: 245, lightGreen: 239, lightBlue: 247, darkRed: 23, darkGreen: 16, darkBlue: 33),
            surface: DesignColor(lightRed: 245, lightGreen: 239, lightBlue: 247, darkRed: 23, darkGreen: 16, darkBlue: 33),
            surfaceLowest: DesignColor(lightRed: 238, lightGreen: 229, lightBlue: 240, darkRed: 31, darkGreen: 24, darkBlue: 42),
            surfaceHigh: DesignColor(lightRed: 255, lightGreen: 255, lightBlue: 255, lightOpacity: 0.70, darkRed: 57, darkGreen: 49, darkBlue: 68, darkOpacity: 0.72),
            primary: DesignColor(red: 247, green: 230, blue: 26),
            onPrimary: DesignColor(red: 36, green: 31, blue: 0),
            focus: DesignColor(lightRed: 110, lightGreen: 102, lightBlue: 0, darkRed: 247, darkGreen: 230, darkBlue: 26),
            secondary: DesignColor(red: 239, green: 103, blue: 26),
            tertiary: DesignColor(red: 136, green: 73, blue: 166),
            text: DesignColor(lightRed: 36, lightGreen: 28, lightBlue: 46, darkRed: 235, darkGreen: 222, darkBlue: 246),
            mutedText: DesignColor(lightRed: 111, lightGreen: 101, lightBlue: 120, darkRed: 170, darkGreen: 160, darkBlue: 180),
            outline: DesignColor(lightRed: 53, lightGreen: 45, lightBlue: 63, lightOpacity: 0.13, darkRed: 255, darkGreen: 255, darkBlue: 255, darkOpacity: 0.10),
            modalShadow: DesignColor(red: 60, green: 26, blue: 135, opacity: 0.2)
        ),
        typography: Typography(
            displayFamily: "Sora",
            bodyFamily: "Hanken Grotesk",
            labelFamily: "Space Grotesk",
            largeDisplaySize: 48,
            mobileDisplaySize: 36,
            headlineSize: 32,
            largeBodySize: 18,
            bodySize: 16,
            labelSize: 12
        ),
        spacing: Spacing(
            extraSmall: 4,
            base: 8,
            small: 12,
            medium: 24,
            large: 48,
            extraLarge: 80,
            gutter: 24,
            phoneMargin: 16,
            largeLayoutMargin: 64
        ),
        shape: Shape(
            smallRadius: 4,
            standardRadius: 8,
            mediumRadius: 12,
            largeRadius: 16,
            extraLargeRadius: 24,
            capsuleRadius: 9_999,
            borderWidth: 1,
            focusOutlineWidth: 3
        ),
        shadow: Shadow(
            modalBlurRadius: 40,
            modalOpacity: 0.2,
            innerHighlightWidth: 1
        ),
        layout: Layout(
            phonePortraitColumns: 2,
            largeLayoutColumns: 3,
            minimumSupportedWidth: 320,
            phoneReferenceWidth: 390,
            tabletReferenceWidth: 1_024
        )
    )
}
