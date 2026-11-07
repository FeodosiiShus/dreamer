import Foundation

nonisolated struct MarkdownPreviewColor: Equatable, Sendable {
    var red: Int
    var green: Int
    var blue: Int
    var alpha: Double

    init(red: Int, green: Int, blue: Int, alpha: Double = 1) {
        self.red = min(max(red, 0), 255)
        self.green = min(max(green, 0), 255)
        self.blue = min(max(blue, 0), 255)
        self.alpha = min(max(alpha, 0), 1)
    }

    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }
        guard digits.count == 6 || digits.count == 8, let value = UInt64(digits, radix: 16) else { return nil }
        if digits.count == 6 {
            self.init(
                red: Int((value >> 16) & 0xFF),
                green: Int((value >> 8) & 0xFF),
                blue: Int(value & 0xFF)
            )
        } else {
            self.init(
                red: Int((value >> 24) & 0xFF),
                green: Int((value >> 16) & 0xFF),
                blue: Int((value >> 8) & 0xFF),
                alpha: Double(value & 0xFF) / 255
            )
        }
    }

    var css: String {
        "rgba(\(red), \(green), \(blue), \(Self.format(alpha)))"
    }

    var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    func withAlpha(_ alpha: Double) -> MarkdownPreviewColor {
        MarkdownPreviewColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var luminance: Double {
        Self.linear(Double(red) / 255) * 0.2126
            + Self.linear(Double(green) / 255) * 0.7152
            + Self.linear(Double(blue) / 255) * 0.0722
    }

    func contrast(with other: MarkdownPreviewColor) -> Double {
        let first = luminance
        let second = other.luminance
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    func mixed(with other: MarkdownPreviewColor, fraction: Double) -> MarkdownPreviewColor {
        func blend(_ lhs: Int, _ rhs: Int) -> Int {
            Int((Double(lhs) * (1 - fraction) + Double(rhs) * fraction).rounded())
        }
        return MarkdownPreviewColor(
            red: blend(red, other.red),
            green: blend(green, other.green),
            blue: blend(blue, other.blue)
        )
    }

    func contrasted(by coefficient: Double) -> MarkdownPreviewColor {
        func adjust(_ channel: Int) -> Int {
            Int(coefficient * (Double(channel) - 128) + 128)
        }
        return MarkdownPreviewColor(red: adjust(red), green: adjust(green), blue: adjust(blue), alpha: alpha)
    }

    func brighter(tones: Int) -> MarkdownPreviewColor {
        tuningBrightness(tones: tones, factor: 1.1)
    }

    func darker(tones: Int) -> MarkdownPreviewColor {
        tuningBrightness(tones: tones, factor: 1 / 1.1)
    }

    func ensuringContrast(against background: MarkdownPreviewColor, atLeast required: Double) -> MarkdownPreviewColor {
        let shiftBrighter = luminance >= background.luminance
        var tones = 0
        var shifted = self
        while shifted.contrast(with: background) < required {
            tones += 1
            let next = shiftBrighter ? brighter(tones: tones) : darker(tones: tones)
            if next == shifted { break }
            shifted = next
        }
        return shifted
    }

    private func tuningBrightness(tones: Int, factor: Float) -> MarkdownPreviewColor {
        let components = Self.hsb(red: red, green: green, blue: blue)
        var brightness = components.2
        for _ in 0..<max(tones, 0) {
            brightness = min(max(factor * brightness, 0), 1)
            if brightness == 0 || brightness == 1 { break }
        }
        let rgb = Self.rgb(hue: components.0, saturation: components.1, brightness: brightness)
        return MarkdownPreviewColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }

    private static func hsb(red: Int, green: Int, blue: Int) -> (Float, Float, Float) {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let brightness = Float(maximum) / 255
        let saturation = maximum == 0 ? 0 : Float(maximum - minimum) / Float(maximum)
        var hue: Float = 0
        if saturation != 0 {
            let span = Float(maximum - minimum)
            let redc = Float(maximum - red) / span
            let greenc = Float(maximum - green) / span
            let bluec = Float(maximum - blue) / span
            if red == maximum {
                hue = bluec - greenc
            } else if green == maximum {
                hue = 2 + redc - bluec
            } else {
                hue = 4 + greenc - redc
            }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, saturation, brightness)
    }

    private static func rgb(hue: Float, saturation: Float, brightness: Float) -> (red: Int, green: Int, blue: Int) {
        func scaled(_ value: Float) -> Int { Int(value * 255 + 0.5) }
        if saturation == 0 {
            let value = scaled(brightness)
            return (value, value, value)
        }
        let sector = (hue - hue.rounded(.down)) * 6
        let fraction = sector - sector.rounded(.down)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - saturation * fraction)
        let t = brightness * (1 - saturation * (1 - fraction))
        switch Int(sector) {
        case 0: return (scaled(brightness), scaled(t), scaled(p))
        case 1: return (scaled(q), scaled(brightness), scaled(p))
        case 2: return (scaled(p), scaled(brightness), scaled(t))
        case 3: return (scaled(p), scaled(q), scaled(brightness))
        case 4: return (scaled(t), scaled(p), scaled(brightness))
        default: return (scaled(brightness), scaled(p), scaled(q))
        }
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func format(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(value)
    }
}

nonisolated struct MarkdownPreviewAccents: Equatable, Sendable {
    var link: MarkdownPreviewColor
    var accent: MarkdownPreviewColor
    var info: MarkdownPreviewColor
    var separator: MarkdownPreviewColor
    var warning: MarkdownPreviewColor
}

nonisolated struct MarkdownPreviewPalette: Equatable, Sendable {
    static let minimumBorderContrast = 3.0
    static let darkFenceAlpha = 0.1
    static let lightFenceAlpha = 0.25
    static let fenceTint = MarkdownPreviewColor(red: 212, green: 222, blue: 231)

    var isDark: Bool
    var fontSize: Int
    var background: MarkdownPreviewColor
    var foreground: MarkdownPreviewColor
    var link: MarkdownPreviewColor
    var info: MarkdownPreviewColor
    var separator: MarkdownPreviewColor
    var fenceBackground: MarkdownPreviewColor
    var highlightBackground: MarkdownPreviewColor
    var selection: MarkdownPreviewColor

    init(
        isDark: Bool,
        fontSize: Int,
        background: MarkdownPreviewColor,
        foreground: MarkdownPreviewColor,
        selection: MarkdownPreviewColor,
        accents: MarkdownPreviewAccents
    ) {
        self.isDark = isDark
        self.fontSize = fontSize
        self.background = background
        self.foreground = foreground
        self.selection = selection
        self.link = accents.link
        self.info = accents.info
        self.fenceBackground = Self.fenceTint.withAlpha(isDark ? Self.darkFenceAlpha : Self.lightFenceAlpha)
        self.highlightBackground = accents.warning.withAlpha(isDark ? 0.3 : 0.35)
        self.separator = accents.separator.ensuringContrast(
            against: background,
            atLeast: Self.minimumBorderContrast
        )
    }

    init?(theme: Theme, fontSize: Int, islandsAccents: MarkdownPreviewAccents) {
        guard let background = MarkdownPreviewColor(hex: theme.editor.background.color),
              let foreground = MarkdownPreviewColor(hex: theme.editor.text.color),
              let selection = MarkdownPreviewColor(hex: theme.editor.selection.color) else { return nil }
        let isDark = theme.appearance == .dark
        let accents = isDark
            ? islandsAccents
            : MarkdownPreviewAccents(
                link: islandsAccents.accent,
                accent: islandsAccents.accent,
                info: foreground.contrasted(by: 0.6),
                separator: background.mixed(with: foreground, fraction: 0.15),
                warning: islandsAccents.warning
            )
        self.init(
            isDark: isDark,
            fontSize: fontSize,
            background: background,
            foreground: foreground,
            selection: selection,
            accents: accents
        )
    }
}

nonisolated enum MarkdownPreviewStyles {
    static func stylesheet(palette: MarkdownPreviewPalette) -> String {
        baseStylesheet + "\n" + themeStylesheet(palette: palette)
    }

    static func themeStylesheet(palette: MarkdownPreviewPalette) -> String {
        let background = palette.background.css
        let foreground = palette.foreground.css
        let link = palette.link.css
        let separator = palette.separator.css
        return """
        :root {
          color-scheme: \(palette.isDark ? "dark" : "light");
          --default-font-size: \(palette.fontSize)px;
        }

        html {
            background-color: \(background);
        }

        body {
            background-color: \(background);
            font-size: var(--default-font-size) !important;
        }

        body, p, blockquote, ul, ol, dl, table, pre, code, tr  {
            color: \(foreground);
        }

        a {
            color: \(link);
        }

        table td, table th {
          border: 1px solid \(separator);
        }

        hr {
          background-color: \(separator);
        }

        kbd, tr {
          border: 1px solid \(separator);
        }

        h6 {
            color: \(palette.info.css);
        }

        blockquote {
          border-left: 2px solid \(palette.link.withAlpha(0.4).css);
        }

        input[type="checkbox"]:checked {
          border-color: \(link);
          background-color: \(link);
        }

        input[type="checkbox"]:checked::after {
          border-color: \(background);
        }

        blockquote, code, pre {
          background-color: \(palette.fenceBackground.css);
        }

        blockquote table th,
        blockquote table td {
          background-color: \(background);
        }

        mark {
          background-color: \(palette.highlightBackground.css);
          color: inherit;
        }

        ::selection {
          background-color: \(palette.selection.css);
        }
        """
    }

    static let baseStylesheet = """
    body {
      -webkit-text-size-adjust: 100%;
      font-family: Helvetica, Arial, freesans, sans-serif;
      font-size: 14px;
      line-height: 1.6;
      word-wrap: break-word;
      margin: 0 2em;
    }

    strong {
      font-weight: bold;
    }

    img {
      border: 0;
    }

    input {
      color: inherit;
      font: inherit;
      margin: 0;
      line-height: normal;
    }

    html input[disabled] {
      cursor: default;
    }

    input[type="checkbox"] {
      appearance: none;
      -webkit-appearance: none;
      box-sizing: border-box;
      width: 14px;
      height: 14px;
      margin: 0;
      padding: 0;
      border: 1px solid currentColor;
      border-radius: 3px;
      position: relative;
      vertical-align: middle;
    }

    input[type="checkbox"]:checked::after {
      content: "";
      position: absolute;
      left: 3px;
      top: 0;
      width: 4px;
      height: 8px;
      border-style: solid;
      border-width: 0 2px 2px 0;
      transform: rotate(45deg);
    }

    body * {
      box-sizing: border-box;
    }

    input {
      font: 13px/1.4 Helvetica, arial, nimbussansl, liberationsans, freesans, clean, sans-serif;
    }

    a {
      text-decoration: none;
    }

    a:hover,
    a:active {
      text-decoration: underline;
    }

    hr {
      height: 1px;
      padding: 0;
      margin: 20px 0;
      border: 0 none;
    }

    hr:before {
      display: table;
      content: "";
    }

    hr:after {
      display: table;
      clear: both;
      content: "";
    }

    blockquote {
        margin: 0;
    }

    ul,
    ol {
      padding: 0;
      margin-top: 0;
      margin-bottom: 0;
    }

    ol ol,
    ul ol {
      list-style-type: lower-roman;
    }

    ul ul ol,
    ul ol ol,
    ol ul ol,
    ol ol ol {
      list-style-type: lower-alpha;
    }

    dd {
      margin-left: 0;
    }

    body > *:first-child {
      margin-top: 0 !important;
    }

    body > *:last-child {
      margin-bottom: 0 !important;
    }

    h1,
    h2,
    h3,
    h4,
    h5,
    h6 {
      position: relative;
      margin-top: 1em;
      margin-bottom: 16px;
      font-weight: bold;
      line-height: 1.4;
    }

    h1 {
      font-size: 2.2em;
      padding-top: 0.6em;
    }

    h2 {
      font-size: 1.8em;
      line-height: 1.2;
      padding-top: 0.6em;
    }

    h3 {
      font-size: 1.3em;
      line-height: 1;
      padding-top: 0.6em;
    }

    h4 {
      font-size: 1em;
    }

    h5 {
      font-size: 1em;
    }

    h6 {
      font-size: 1em;
    }

    p,
    blockquote,
    ul,
    ol,
    dl,
    table,
    pre {
      margin-top: 16px;
      margin-bottom: 16px;
    }

    ul,
    ol {
      padding-left: 2em;
    }

    ul ul,
    ul ol,
    ol ol,
    ol ul {
      margin-top: 0;
      margin-bottom: 0;
    }

    li > p {
      margin-top: 0;
      margin-bottom: 0;
    }

    dl {
      padding: 0;
    }

    dl dt {
      padding: 0;
      margin-top: 16px;
      font-size: 1em;
      font-style: italic;
      font-weight: bold;
    }

    dl dd {
      padding: 0 16px;
      margin-bottom: 16px;
    }

    blockquote {
      padding: 10px 10px 10px 16px;
      border-left: 2px solid;
      border-radius: 0 3px 3px 0;
    }

    blockquote > :first-child {
      margin-top: 0;
    }

    blockquote > :last-child {
      margin-bottom: 0;
    }

    table {
      display: block;
      width: 100%;
      overflow: auto;
      word-break: normal;
      border-collapse: collapse;
      border-spacing: 0;
      font-size: 1em;
    }

    table th {
      font-weight: bold;
    }

    table th,
    table td {
      padding: 6px 13px;
      background: transparent;
    }

    table tr {
      border-top: 1px solid;
    }

    img {
      max-width: 100%;
      box-sizing: border-box;
    }

    code {
      font: 0.9em "JetBrains Mono", Consolas, "Liberation Mono", Menlo, Courier, monospace;
      font-weight: inherit;
      font-style: inherit;
      padding: 0.2em 0.4em;
      margin: 2px;
      border-radius: 3px;
    }

    pre > code {
      padding: 0;
      margin: 0;
      font-size: 100%;
      word-break: normal;
      white-space: pre;
      background: transparent;
      border: 0;
    }

    .highlight {
      margin-bottom: 16px;
    }

    .highlight pre,
    pre {
      font: 0.85em "JetBrains Mono", Consolas, "Liberation Mono", Menlo, Courier, monospace;
      padding: 16px;
      overflow: auto;
      line-height: 1.45;
      border-radius: 3px;
    }

    pre code {
      display: inline;
      max-width: initial;
      padding: 0;
      margin: 0;
      overflow: initial;
      line-height: inherit;
      word-wrap: normal;
      background-color: transparent;
      border: 0;
    }

    pre code:before,
    pre code:after {
      content: normal;
    }

    kbd {
      font: 0.9em "JetBrains Mono", Consolas, "Liberation Mono", Menlo, Courier, monospace;
      padding: 0.2em 0.4em;
      margin: 2px;
      border-radius: 3px;
    }

    .task-list-item {
      list-style-type: none;
    }

    .task-list-item + .task-list-item {
      margin-top: 3px;
    }

    .task-list-item input {
      margin: 0 0.35em 0.25em -0.6em;
      vertical-align: middle;
    }

    del {
      text-decoration: line-through;
    }
    """
}
