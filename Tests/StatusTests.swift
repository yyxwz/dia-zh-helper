import Foundation

@main struct StatusTests {
    static func main() {
        let signature = "签名：有效的统一 ad-hoc 签名\n"
        let complete = "版本：1.57.1 (90935)\n补丁状态：applied\n覆盖级别：core\n"
        assert(!PatchStatus(complete + signature).isVerified, "Old state alone must never be green")
        assert(!PatchStatus(complete + "签名：Dia 官方签名\n资源校验：通过").isVerified)
        assert(!PatchStatus(complete + signature + "资源校验：失败").isVerified)
        let interrupted = PatchStatus("补丁状态：applying\n" + signature + "资源校验：通过")
        assert(!interrupted.isVerified && interrupted.title.contains("未完成"))
        let verified = PatchStatus(complete + signature + "资源校验：通过\n启动检查：待验证")
        assert(verified.isVerified && verified.title == "核心汉化已校验")
        assert(verified.detail.contains("待验证") && verified.detail.contains("仍可能为英文"))
        let waiting = PatchStatus(complete + signature + "资源校验：通过\n启动检查：等待窗口或系统授权")
        assert(waiting.isVerified && waiting.detail.contains("等待窗口或系统授权"))
        print("Status regressions passed (stale state, official overwrite, interrupted install, partial coverage, pending startup).")
    }
}
