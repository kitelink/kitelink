import XCTest
@testable import KiteKit

final class KiteKitTests: XCTestCase {
    func testNodeNames() {
        XCTAssertEqual(NodeName("🇯🇵 日本 IEPL 专线 1").region, "JP")
        XCTAssertEqual(NodeName("🇯🇵 日本 IEPL 专线 1").title, "日本 IEPL 专线 1")
        XCTAssertEqual(NodeName("4台湾-专线(AnyTLS)").region, "TW")
        XCTAssertEqual(NodeName("JP-A").region, "JP")
        XCTAssertEqual(NodeName("12美国西雅图-优化(hy2)").region, "US")
        XCTAssertEqual(NodeName("Traffic: 52.34 GB | 400 GB").region, nil)
        XCTAssertEqual(NodeName("[🇭🇰] 01").title, "01")
        XCTAssertEqual(NodeName.flag(for: "SG"), "🇸🇬")
        XCTAssertEqual(NodeName("ID-A").region, "ID")
        XCTAssertEqual(NodeName("IN-A").region, "IN")
        XCTAssertEqual(NodeName("UK-A").region, "GB")
        XCTAssertEqual(NodeName("DIRECT").region, nil)
        XCTAssertEqual(NodeName("Expire: 2027-04-04").region, nil)
    }

    func testUserInfo() {
        let u = SubscriptionUsage.parse("upload=1024; download=2147483648; total=107374182400; expire=1798761600")!
        XCTAssertEqual(u.download, 2147483648)
        XCTAssertEqual(u.total, 107374182400)
        XCTAssertNotNil(u.expire)
    }

    func testFilename() {
        XCTAssertEqual(Subscription.parseFilename("attachment;filename*=UTF-8''%E9%A3%8E%E7%AD%9D%E7%BA%BF.com"), "风筝线.com")
        XCTAssertEqual(Subscription.parseFilename("attachment; filename=\"Sky Atlas.yaml\""), "Sky Atlas")
    }

    func testBuild() throws {
        let profile = """
        port: 7890
        mixed-port: 7893
        external-controller: 0.0.0.0:9090
        proxies:
          - {name: a, type: ss, server: x, port: 1, cipher: aes-128-gcm, password: p}
        proxy-groups:
          - {name: Proxies, type: select, proxies: [a]}
        rules:
          - MATCH,Proxies
        """
        let override = """
        prepend-rules:
          - DOMAIN-SUFFIX,example.com,DIRECT
        dns:
          enable: true
        """
        var core = CoreSettings()
        core.mixedPort = 7777
        let r = try ConfigBuilder.build(profileYAML: profile, globalOverride: override, profileOverride: nil, core: core, secret: "s")
        XCTAssertTrue(r.yaml.contains("mixed-port: 7777"))
        XCTAssertFalse(r.yaml.contains("port: 7890"))
        XCTAssertTrue(r.yaml.contains("external-controller: 127.0.0.1:9090"))
        XCTAssertTrue(r.yaml.range(of: "- DOMAIN-SUFFIX,example.com,DIRECT\n- MATCH,Proxies")! .lowerBound > r.yaml.startIndex)
        XCTAssertTrue(r.yaml.contains("store-selected: true"))
        XCTAssertEqual(ConfigBuilder.groups(in: profile).first?.name, "Proxies")
    }

    func testValidate() {
        XCTAssertThrowsError(try Subscription.validate("<html><body>hi</body></html>"))
        XCTAssertThrowsError(try Subscription.validate("dm1lc3M6Ly9hYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5ejEyMzQ1Njc4OTA="))
        XCTAssertNoThrow(try Subscription.validate("proxies:\n  - {name: a}"))
    }
}
