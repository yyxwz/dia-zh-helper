import Foundation

struct PatchStatus {
    let fields: [String: String]
    init(_ output: String) {
        var values: [String: String] = [:]
        for line in output.components(separatedBy: .newlines) {
            guard let separator = line.range(of: "："), !line.hasPrefix("[") else { continue }
            values[String(line[..<separator.lowerBound])] = String(line[separator.upperBound...])
        }
        fields = values
    }
    var version: String { fields["版本"] ?? "未知" }
    var isOfficial: Bool { fields["签名"] == "Dia 官方签名" }
    var isVerified: Bool {
        fields["补丁状态"] == "applied" &&
        fields["签名"] == "有效的统一 ad-hoc 签名" &&
        fields["资源校验"] == "通过"
    }
    var title: String {
        if isVerified {
            return fields["覆盖级别"] == "core" ? "核心汉化已校验" : "补丁资源已校验"
        }
        if fields["补丁状态"] == "applying" { return "上次安装未完成，点击修复" }
        if isOfficial { return "官方版尚未汉化，点击修复" }
        return "补丁验证失败，需要修复"
    }
    var detail: String {
        let startup = isVerified && fields["启动检查"] != "通过" ? " · \(fields["启动检查"] ?? "待启动验证")" : ""
        return "Dia \(version) · \(fields["覆盖级别"] ?? "未知")\(startup)\n核心汉化覆盖菜单和部分界面，部分设置与 AI 页面仍可能为英文。"
    }
}
