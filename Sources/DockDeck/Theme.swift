import Cocoa
import SwiftTerm

struct Theme {
    let id: String
    let isDark: Bool
    let name: String
    let panelTintColor: NSColor
    let foregroundColor: NSColor
    let ansiPalette: [Color]

    var chromeTintColor: NSColor {
        isDark ? NSColor.white.withAlphaComponent(0.55) : NSColor.black.withAlphaComponent(0.4)
    }

    func tintColor(opacity: CGFloat?) -> NSColor {
        panelTintColor.withAlphaComponent(opacity ?? panelTintColor.alphaComponent)
    }
}

extension Theme {
    static let all: [Theme] = [
        .nebula, .green, .dracula, .nord, .gruvboxDark, .solarizedDark, .monokai, .oneDark,
        .tokyoNight, .catppuccinMocha,
        .solarizedLight, .gruvboxLight, .oneLight, .catppuccinLatte, .ayuLight, .githubLight,
        .paperColorLight, .rosePineDawn, .tomorrowLight, .nordLight,
    ]

    static let `default` = Theme.nebula

    static func theme(id: String) -> Theme {
        all.first { $0.id == id } ?? .default
    }

    // MARK: - Dark

    static let nebula = Theme(
        id: "nebula",
        isDark: true,
        name: "Nebula",
        panelTintColor: nsColor(5, 9, 15, alpha: 0.65),
        foregroundColor: .labelColor,
        ansiPalette: [
            ansiColor(20, 24, 33),
            ansiColor(198, 74, 90),
            ansiColor(79, 157, 105),
            ansiColor(196, 154, 62),
            ansiColor(58, 124, 165),
            ansiColor(133, 110, 168),
            ansiColor(69, 156, 156),
            ansiColor(196, 190, 172),
            ansiColor(75, 87, 99),
            ansiColor(222, 102, 118),
            ansiColor(111, 191, 135),
            ansiColor(224, 186, 105),
            ansiColor(95, 168, 211),
            ansiColor(169, 143, 201),
            ansiColor(114, 214, 207),
            ansiColor(230, 224, 208),
        ]
    )

    static let green = Theme(
        id: "green",
        isDark: true,
        name: "Terminal Green",
        panelTintColor: nsColor(0, 8, 0, alpha: 0.82),
        foregroundColor: nsColor(70, 255, 120),
        ansiPalette: [
            ansiColor(0, 0, 0),
            ansiColor(0, 110, 40),
            ansiColor(0, 170, 60),
            ansiColor(40, 190, 70),
            ansiColor(0, 140, 90),
            ansiColor(60, 170, 110),
            ansiColor(0, 190, 150),
            ansiColor(170, 220, 170),
            ansiColor(50, 80, 50),
            ansiColor(40, 220, 80),
            ansiColor(80, 255, 120),
            ansiColor(140, 255, 140),
            ansiColor(60, 220, 160),
            ansiColor(120, 255, 180),
            ansiColor(100, 255, 200),
            ansiColor(210, 255, 210),
        ]
    )

    static let dracula = Theme(
        id: "dracula",
        isDark: true,
        name: "Dracula",
        panelTintColor: nsColor(40, 42, 54, alpha: 0.78),
        foregroundColor: nsColor(248, 248, 242),
        ansiPalette: [
            ansiColor(33, 34, 44),
            ansiColor(255, 85, 85),
            ansiColor(80, 250, 123),
            ansiColor(241, 250, 140),
            ansiColor(189, 147, 249),
            ansiColor(255, 121, 198),
            ansiColor(139, 233, 253),
            ansiColor(248, 248, 242),
            ansiColor(98, 114, 164),
            ansiColor(255, 110, 110),
            ansiColor(105, 255, 148),
            ansiColor(255, 255, 165),
            ansiColor(214, 172, 255),
            ansiColor(255, 146, 223),
            ansiColor(164, 255, 255),
            ansiColor(255, 255, 255),
        ]
    )

    static let nord = Theme(
        id: "nord",
        isDark: true,
        name: "Nord",
        panelTintColor: nsColor(46, 52, 64, alpha: 0.78),
        foregroundColor: nsColor(216, 222, 233),
        ansiPalette: [
            ansiColor(59, 66, 82),
            ansiColor(191, 97, 106),
            ansiColor(163, 190, 140),
            ansiColor(235, 203, 139),
            ansiColor(129, 161, 193),
            ansiColor(180, 142, 173),
            ansiColor(136, 192, 208),
            ansiColor(229, 233, 240),
            ansiColor(76, 86, 106),
            ansiColor(191, 97, 106),
            ansiColor(163, 190, 140),
            ansiColor(235, 203, 139),
            ansiColor(129, 161, 193),
            ansiColor(180, 142, 173),
            ansiColor(143, 188, 187),
            ansiColor(236, 239, 244),
        ]
    )

    static let gruvboxDark = Theme(
        id: "gruvbox-dark",
        isDark: true,
        name: "Gruvbox Dark",
        panelTintColor: nsColor(40, 40, 40, alpha: 0.82),
        foregroundColor: nsColor(235, 219, 178),
        ansiPalette: [
            ansiColor(40, 40, 40),
            ansiColor(204, 36, 29),
            ansiColor(152, 151, 26),
            ansiColor(215, 153, 33),
            ansiColor(69, 133, 136),
            ansiColor(177, 98, 134),
            ansiColor(104, 157, 106),
            ansiColor(168, 153, 132),
            ansiColor(146, 131, 116),
            ansiColor(251, 73, 52),
            ansiColor(184, 187, 38),
            ansiColor(250, 189, 47),
            ansiColor(131, 165, 152),
            ansiColor(211, 134, 155),
            ansiColor(142, 192, 124),
            ansiColor(235, 219, 178),
        ]
    )

    static let solarizedDark = Theme(
        id: "solarized-dark",
        isDark: true,
        name: "Solarized Dark",
        panelTintColor: nsColor(0, 43, 54, alpha: 0.82),
        foregroundColor: nsColor(131, 148, 150),
        ansiPalette: [
            ansiColor(7, 54, 66),
            ansiColor(220, 50, 47),
            ansiColor(133, 153, 0),
            ansiColor(181, 137, 0),
            ansiColor(38, 139, 210),
            ansiColor(211, 54, 130),
            ansiColor(42, 161, 152),
            ansiColor(238, 232, 213),
            ansiColor(0, 43, 54),
            ansiColor(203, 75, 22),
            ansiColor(88, 110, 117),
            ansiColor(101, 123, 131),
            ansiColor(131, 148, 150),
            ansiColor(108, 113, 196),
            ansiColor(147, 161, 161),
            ansiColor(253, 246, 227),
        ]
    )

    static let monokai = Theme(
        id: "monokai",
        isDark: true,
        name: "Monokai",
        panelTintColor: nsColor(39, 40, 34, alpha: 0.82),
        foregroundColor: nsColor(248, 248, 242),
        ansiPalette: [
            ansiColor(39, 40, 34),
            ansiColor(249, 38, 114),
            ansiColor(166, 226, 46),
            ansiColor(244, 191, 117),
            ansiColor(102, 217, 239),
            ansiColor(174, 129, 255),
            ansiColor(161, 239, 228),
            ansiColor(248, 248, 242),
            ansiColor(117, 113, 94),
            ansiColor(249, 38, 114),
            ansiColor(166, 226, 46),
            ansiColor(244, 191, 117),
            ansiColor(102, 217, 239),
            ansiColor(174, 129, 255),
            ansiColor(161, 239, 228),
            ansiColor(249, 248, 245),
        ]
    )

    static let oneDark = Theme(
        id: "one-dark",
        isDark: true,
        name: "One Dark",
        panelTintColor: nsColor(40, 44, 52, alpha: 0.82),
        foregroundColor: nsColor(171, 178, 191),
        ansiPalette: [
            ansiColor(40, 44, 52),
            ansiColor(224, 108, 117),
            ansiColor(152, 195, 121),
            ansiColor(229, 192, 123),
            ansiColor(97, 175, 239),
            ansiColor(198, 120, 221),
            ansiColor(86, 182, 194),
            ansiColor(171, 178, 191),
            ansiColor(92, 99, 112),
            ansiColor(224, 108, 117),
            ansiColor(152, 195, 121),
            ansiColor(229, 192, 123),
            ansiColor(97, 175, 239),
            ansiColor(198, 120, 221),
            ansiColor(86, 182, 194),
            ansiColor(255, 255, 255),
        ]
    )

    static let tokyoNight = Theme(
        id: "tokyo-night",
        isDark: true,
        name: "Tokyo Night",
        panelTintColor: nsColor(26, 27, 38, alpha: 0.82),
        foregroundColor: nsColor(192, 202, 245),
        ansiPalette: [
            ansiColor(21, 22, 30),
            ansiColor(247, 118, 142),
            ansiColor(158, 206, 106),
            ansiColor(224, 175, 104),
            ansiColor(122, 162, 247),
            ansiColor(187, 154, 247),
            ansiColor(125, 207, 255),
            ansiColor(169, 177, 214),
            ansiColor(65, 72, 104),
            ansiColor(247, 118, 142),
            ansiColor(158, 206, 106),
            ansiColor(224, 175, 104),
            ansiColor(122, 162, 247),
            ansiColor(187, 154, 247),
            ansiColor(125, 207, 255),
            ansiColor(192, 202, 245),
        ]
    )

    static let catppuccinMocha = Theme(
        id: "catppuccin-mocha",
        isDark: true,
        name: "Catppuccin Mocha",
        panelTintColor: nsColor(30, 30, 46, alpha: 0.82),
        foregroundColor: nsColor(205, 214, 244),
        ansiPalette: [
            ansiColor(69, 71, 90),
            ansiColor(243, 139, 168),
            ansiColor(166, 227, 161),
            ansiColor(249, 226, 175),
            ansiColor(137, 180, 250),
            ansiColor(245, 194, 231),
            ansiColor(148, 226, 213),
            ansiColor(186, 194, 222),
            ansiColor(88, 91, 112),
            ansiColor(243, 139, 168),
            ansiColor(166, 227, 161),
            ansiColor(249, 226, 175),
            ansiColor(137, 180, 250),
            ansiColor(245, 194, 231),
            ansiColor(148, 226, 213),
            ansiColor(166, 173, 200),
        ]
    )

    // MARK: - Light

    static let solarizedLight = Theme(
        id: "solarized-light",
        isDark: false,
        name: "Solarized Light",
        panelTintColor: nsColor(253, 246, 227, alpha: 0.85),
        foregroundColor: nsColor(101, 123, 131),
        ansiPalette: [
            ansiColor(7, 54, 66),
            ansiColor(220, 50, 47),
            ansiColor(133, 153, 0),
            ansiColor(181, 137, 0),
            ansiColor(38, 139, 210),
            ansiColor(211, 54, 130),
            ansiColor(42, 161, 152),
            ansiColor(238, 232, 213),
            ansiColor(0, 43, 54),
            ansiColor(203, 75, 22),
            ansiColor(88, 110, 117),
            ansiColor(101, 123, 131),
            ansiColor(131, 148, 150),
            ansiColor(108, 113, 196),
            ansiColor(147, 161, 161),
            ansiColor(253, 246, 227),
        ]
    )

    static let gruvboxLight = Theme(
        id: "gruvbox-light",
        isDark: false,
        name: "Gruvbox Light",
        panelTintColor: nsColor(251, 241, 199, alpha: 0.85),
        foregroundColor: nsColor(60, 56, 54),
        ansiPalette: [
            ansiColor(251, 241, 199),
            ansiColor(204, 36, 29),
            ansiColor(152, 151, 26),
            ansiColor(215, 153, 33),
            ansiColor(69, 133, 136),
            ansiColor(177, 98, 134),
            ansiColor(104, 157, 106),
            ansiColor(124, 111, 100),
            ansiColor(146, 131, 116),
            ansiColor(157, 0, 6),
            ansiColor(121, 116, 14),
            ansiColor(181, 118, 20),
            ansiColor(7, 102, 120),
            ansiColor(143, 63, 113),
            ansiColor(66, 123, 88),
            ansiColor(60, 56, 54),
        ]
    )

    static let oneLight = Theme(
        id: "one-light",
        isDark: false,
        name: "One Light",
        panelTintColor: nsColor(250, 250, 250, alpha: 0.85),
        foregroundColor: nsColor(56, 58, 66),
        ansiPalette: [
            ansiColor(250, 250, 250),
            ansiColor(228, 86, 73),
            ansiColor(80, 161, 79),
            ansiColor(193, 132, 1),
            ansiColor(64, 120, 242),
            ansiColor(166, 38, 164),
            ansiColor(1, 132, 188),
            ansiColor(56, 58, 66),
            ansiColor(160, 161, 167),
            ansiColor(228, 86, 73),
            ansiColor(80, 161, 79),
            ansiColor(193, 132, 1),
            ansiColor(64, 120, 242),
            ansiColor(166, 38, 164),
            ansiColor(1, 132, 188),
            ansiColor(9, 10, 11),
        ]
    )

    static let catppuccinLatte = Theme(
        id: "catppuccin-latte",
        isDark: false,
        name: "Catppuccin Latte",
        panelTintColor: nsColor(239, 241, 245, alpha: 0.85),
        foregroundColor: nsColor(76, 79, 105),
        ansiPalette: [
            ansiColor(92, 95, 119),
            ansiColor(210, 15, 57),
            ansiColor(64, 160, 43),
            ansiColor(223, 142, 29),
            ansiColor(30, 102, 245),
            ansiColor(234, 118, 203),
            ansiColor(23, 146, 153),
            ansiColor(172, 176, 190),
            ansiColor(108, 111, 133),
            ansiColor(210, 15, 57),
            ansiColor(64, 160, 43),
            ansiColor(223, 142, 29),
            ansiColor(30, 102, 245),
            ansiColor(234, 118, 203),
            ansiColor(23, 146, 153),
            ansiColor(188, 192, 204),
        ]
    )

    static let ayuLight = Theme(
        id: "ayu-light",
        isDark: false,
        name: "Ayu Light",
        panelTintColor: nsColor(250, 250, 250, alpha: 0.85),
        foregroundColor: nsColor(92, 97, 102),
        ansiPalette: [
            ansiColor(250, 250, 250),
            ansiColor(245, 24, 24),
            ansiColor(134, 179, 0),
            ansiColor(242, 174, 73),
            ansiColor(57, 158, 230),
            ansiColor(163, 122, 204),
            ansiColor(76, 191, 153),
            ansiColor(92, 97, 102),
            ansiColor(171, 176, 182),
            ansiColor(255, 51, 51),
            ansiColor(134, 179, 0),
            ansiColor(242, 174, 73),
            ansiColor(57, 158, 230),
            ansiColor(163, 122, 204),
            ansiColor(76, 191, 153),
            ansiColor(0, 0, 0),
        ]
    )

    static let githubLight = Theme(
        id: "github-light",
        isDark: false,
        name: "GitHub Light",
        panelTintColor: nsColor(255, 255, 255, alpha: 0.85),
        foregroundColor: nsColor(36, 41, 46),
        ansiPalette: [
            ansiColor(36, 41, 46),
            ansiColor(215, 58, 73),
            ansiColor(40, 167, 69),
            ansiColor(219, 171, 9),
            ansiColor(3, 102, 214),
            ansiColor(90, 50, 163),
            ansiColor(27, 124, 131),
            ansiColor(106, 115, 125),
            ansiColor(149, 157, 165),
            ansiColor(203, 36, 49),
            ansiColor(34, 134, 58),
            ansiColor(176, 136, 0),
            ansiColor(0, 92, 197),
            ansiColor(90, 50, 163),
            ansiColor(49, 146, 170),
            ansiColor(209, 213, 218),
        ]
    )

    static let paperColorLight = Theme(
        id: "papercolor-light",
        isDark: false,
        name: "PaperColor Light",
        panelTintColor: nsColor(238, 238, 238, alpha: 0.85),
        foregroundColor: nsColor(68, 68, 68),
        ansiPalette: [
            ansiColor(238, 238, 238),
            ansiColor(175, 0, 0),
            ansiColor(0, 135, 0),
            ansiColor(95, 135, 0),
            ansiColor(0, 135, 175),
            ansiColor(135, 135, 135),
            ansiColor(0, 95, 135),
            ansiColor(68, 68, 68),
            ansiColor(188, 188, 188),
            ansiColor(215, 0, 0),
            ansiColor(215, 0, 135),
            ansiColor(135, 0, 175),
            ansiColor(215, 95, 0),
            ansiColor(95, 175, 95),
            ansiColor(0, 95, 175),
            ansiColor(0, 95, 135),
        ]
    )

    static let rosePineDawn = Theme(
        id: "rose-pine-dawn",
        isDark: false,
        name: "Rosé Pine Dawn",
        panelTintColor: nsColor(250, 244, 237, alpha: 0.85),
        foregroundColor: nsColor(87, 82, 121),
        ansiPalette: [
            ansiColor(242, 233, 225),
            ansiColor(180, 99, 122),
            ansiColor(40, 105, 131),
            ansiColor(234, 157, 52),
            ansiColor(86, 148, 159),
            ansiColor(144, 122, 169),
            ansiColor(215, 130, 126),
            ansiColor(87, 82, 121),
            ansiColor(152, 147, 165),
            ansiColor(180, 99, 122),
            ansiColor(40, 105, 131),
            ansiColor(234, 157, 52),
            ansiColor(86, 148, 159),
            ansiColor(144, 122, 169),
            ansiColor(215, 130, 126),
            ansiColor(121, 117, 147),
        ]
    )

    static let tomorrowLight = Theme(
        id: "tomorrow-light",
        isDark: false,
        name: "Tomorrow",
        panelTintColor: nsColor(255, 255, 255, alpha: 0.85),
        foregroundColor: nsColor(77, 77, 76),
        ansiPalette: [
            ansiColor(0, 0, 0),
            ansiColor(200, 40, 41),
            ansiColor(113, 140, 0),
            ansiColor(234, 183, 0),
            ansiColor(66, 113, 174),
            ansiColor(137, 89, 168),
            ansiColor(62, 153, 159),
            ansiColor(197, 200, 198),
            ansiColor(150, 152, 150),
            ansiColor(200, 40, 41),
            ansiColor(113, 140, 0),
            ansiColor(234, 183, 0),
            ansiColor(66, 113, 174),
            ansiColor(137, 89, 168),
            ansiColor(62, 153, 159),
            ansiColor(255, 255, 255),
        ]
    )

    static let nordLight = Theme(
        id: "nord-light",
        isDark: false,
        name: "Nord Light",
        panelTintColor: nsColor(236, 239, 244, alpha: 0.85),
        foregroundColor: nsColor(46, 52, 64),
        ansiPalette: [
            ansiColor(59, 66, 82),
            ansiColor(191, 97, 106),
            ansiColor(163, 190, 140),
            ansiColor(235, 203, 139),
            ansiColor(129, 161, 193),
            ansiColor(180, 142, 173),
            ansiColor(136, 192, 208),
            ansiColor(229, 233, 240),
            ansiColor(76, 86, 106),
            ansiColor(191, 97, 106),
            ansiColor(163, 190, 140),
            ansiColor(235, 203, 139),
            ansiColor(129, 161, 193),
            ansiColor(180, 142, 173),
            ansiColor(143, 188, 187),
            ansiColor(46, 52, 64),
        ]
    )
}

private func ansiColor(_ red: UInt16, _ green: UInt16, _ blue: UInt16) -> Color {
    Color(red: red * 257, green: green * 257, blue: blue * 257)
}

private func nsColor(_ red: Int, _ green: Int, _ blue: Int, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        calibratedRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255,
        alpha: alpha)
}
