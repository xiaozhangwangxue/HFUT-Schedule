import XCTest
@testable import HFUTSchedule

final class WebVPNURLConverterTests: XCTestCase {
    private let root = "https://webvpn.hfut.edu.cn/"
    private let keyHex = "77726476706e69737468656265737421"

    func testAESCFBKnownVectorsMatchUpstreamAndIndependentOpenSSL() throws {
        // AES-128-CFB with the upstream public key and IV. Expected ciphertext
        // was independently produced with OpenSSL, not the Swift converter.
        let fixtures = [
            ("http://jxglstu.hfut.edu.cn/eams5-student/", "http", "faef469034247d1e760e9cb8d6502720ede479", "/eams5-student/"),
            ("https://example.org/", "https", "f5ef4091373c6d1e711a8e", "/"),
            ("http://210.45.242.5/", "http", "a2a611d2736526022a5ac7f9", "/")
        ]
        for (source, scheme, cipher, path) in fixtures {
            XCTAssertEqual(WebVPNURLConverter.convert(source)?.absoluteString, root + scheme + "/" + keyHex + cipher + path)
        }
    }

    func testManualConversionDoesNotBroadenAutomaticNavigationPolicy() throws {
        let external = try XCTUnwrap(URL(string: "https://example.org/notice"))
        let campus = try XCTUnwrap(URL(string: "https://jxglstu.hfut.edu.cn/eams5-student/"))
        XCTAssertEqual(WebVPNURLConverter.convertedIfNeeded(external, mode: .webVPN), external)
        XCTAssertEqual(WebVPNURLConverter.convertedIfNeeded(campus, mode: .direct), campus)
        XCTAssertNotEqual(WebVPNURLConverter.convert(external), external)
        XCTAssertEqual(WebVPNURLConverter.convertedIfNeeded(campus, mode: .webVPN), WebVPNURLConverter.convert(campus))
        XCTAssertFalse(WebVPNURLConverter.isCampusResource(URL(string: "https://hfut.edu.cn.example.org/")!))
    }

    func testNormalizedInputRequiresCompleteHTTPURLWithoutCredentials() {
        XCTAssertEqual(WebVPNURLConverter.normalizedInput(" \nhttps://example.org/a\n ")?.host, "example.org")
        let invalid = ["", "example.org/a", "/relative", "//example.org/a", "https:example.org",
                       "ftp://example.org/a", "javascript:alert(1)", "file:///tmp/file", "data:text/plain,test",
                       "https://user@example.org/a", "https://user:fixture@example.org/a", "https://example.org:0/a",
                       "https://example.org:65536/a", "https://example.org/%zz", "https://example.org/a b",
                       "https://example.org/a\nhttps://elsewhere.example/", "https://example..org/"]
        for text in invalid { XCTAssertNil(WebVPNURLConverter.normalizedInput(text), "Malformed or unsupported input must be rejected") }
    }

    func testEncodedPathQueryAndFragmentSurviveRoundTripExactly() throws {
        let source = try XCTUnwrap(URL(string: "https://example.org/a%2Fb//%E4%B8%AD%E6%96%87?x=a%2Bb&x=2&percent=%2525#%E7%89%87%E6%AE%B5%2Fpart"))
        let converted = try XCTUnwrap(WebVPNURLConverter.convert(source))
        let restored = try XCTUnwrap(WebVPNURLConverter.restore(converted))
        let a = try XCTUnwrap(URLComponents(url: source, resolvingAgainstBaseURL: false))
        let b = try XCTUnwrap(URLComponents(url: restored, resolvingAgainstBaseURL: false))
        XCTAssertEqual(a.percentEncodedPath, b.percentEncodedPath)
        XCTAssertEqual(a.percentEncodedQuery, b.percentEncodedQuery)
        XCTAssertEqual(a.percentEncodedFragment, b.percentEncodedFragment)
        XCTAssertEqual(restored.absoluteString, source.absoluteString)
    }

    func testHTTPAndHTTPSPortsAreEncodedInRouteAndRestoredAsPorts() throws {
        for scheme in ["http", "https"] {
            for port in [80, 443, 8443, 65535] {
                let source = try XCTUnwrap(URL(string: "\(scheme)://example.org:\(port)/a?x=1#part"))
                let converted = try XCTUnwrap(WebVPNURLConverter.convert(source))
                XCTAssertTrue(converted.path.hasPrefix("/\(scheme)-\(port)/"))
                let restored = try XCTUnwrap(WebVPNURLConverter.restore(converted))
                XCTAssertEqual(restored.scheme, scheme)
                XCTAssertEqual(restored.port, port)
                XCTAssertEqual(restored.absoluteString, source.absoluteString)
            }
        }
    }

    func testHostOnlyURLsAndEmptyQueryOrFragmentKeepTheirStructure() throws {
        for suffix in ["", "?", "#", "?x=1#part", "/?x=#"] {
            let source = try XCTUnwrap(URL(string: "https://example.org" + suffix))
            let restored = try XCTUnwrap(WebVPNURLConverter.restore(try XCTUnwrap(WebVPNURLConverter.convert(source))))
            let a = try XCTUnwrap(URLComponents(url: source, resolvingAgainstBaseURL: false))
            let b = try XCTUnwrap(URLComponents(url: restored, resolvingAgainstBaseURL: false))
            XCTAssertEqual(b.percentEncodedPath, a.percentEncodedPath.isEmpty ? "/" : a.percentEncodedPath)
            XCTAssertEqual(a.percentEncodedQuery, b.percentEncodedQuery)
            XCTAssertEqual(a.percentEncodedFragment, b.percentEncodedFragment)
        }
    }

    func testUnicodeHostPathQueryAndFragmentNormalizeAndRoundTrip() throws {
        let source = try XCTUnwrap(WebVPNURLConverter.normalizedInput("https://例子.测试/中文?查询=值#片段"))
        let converted = try XCTUnwrap(WebVPNURLConverter.convert(source))
        XCTAssertTrue(converted.path.hasPrefix("/https/" + keyHex + "e8f90cd1212379452e5888e2805b6e7879ed6a31758765/"))
        XCTAssertEqual(WebVPNURLConverter.restore(converted)?.absoluteString, source.absoluteString)
    }

    func testRawUnicodeHostEncodedByAndroidCanAlsoBeRestoredSafely() throws {
        let proxy = root + "https/" + keyHex + "7429aa19eac026d6abe301636d/path"
        XCTAssertEqual(WebVPNURLConverter.restore(proxy)?.host, "xn--fsqu00a.xn--0zwm56d")
    }

    func testIPv6HostAndPortHaveUnambiguousAuthorityOnRestoration() throws {
        let source = try XCTUnwrap(URL(string: "https://[2001:db8::1]:8443/path?x=1#part"))
        let converted = try XCTUnwrap(WebVPNURLConverter.convert(source))
        XCTAssertTrue(converted.path.hasPrefix("/https-8443/" + keyHex + "a2a711cd7d346a082452d8/"))
        XCTAssertEqual(WebVPNURLConverter.restore(converted)?.absoluteString, source.absoluteString)
    }

    func testAlreadyConvertedURLsAndGatewayPagesAreNotWrappedAgain() throws {
        let converted = try XCTUnwrap(WebVPNURLConverter.convert("https://example.org:8443/path?a=1#part"))
        XCTAssertEqual(WebVPNURLConverter.convert(converted), converted)
        XCTAssertEqual(WebVPNURLConverter.convertedIfNeeded(converted, mode: .webVPN), converted)
        let login = try XCTUnwrap(URL(string: root + "login?cas_login=true"))
        XCTAssertEqual(WebVPNURLConverter.convert(login), login)
        XCTAssertNil(WebVPNURLConverter.restore(login))
    }

    func testRestorationRequiresTheSchoolHTTPSGatewayOrigin() throws {
        let path = "https/" + keyHex + "f5ef4091373c6d1e711a8e/"
        let invalidOrigins = ["https://example.org/", "https://webvpn.hfut.edu.cn.example.org/",
                              "http://webvpn.hfut.edu.cn/", "https://webvpn.hfut.edu.cn:444/",
                              "https://user@webvpn.hfut.edu.cn/"]
        for origin in invalidOrigins { XCTAssertNil(WebVPNURLConverter.restore(origin + path)) }
        XCTAssertNotNil(WebVPNURLConverter.restore(root + path))
    }

    func testMalformedEncryptedRoutesAndUnsupportedPortsAreRejected() {
        let cipher = "f5ef4091373c6d1e711a8e"
        for route in ["ftp", "https-", "https-port", "https-0", "https-65536", "https-123456", "https-80-extra"] {
            XCTAssertNil(WebVPNURLConverter.restore(root + route + "/" + keyHex + cipher + "/"))
        }
        for token in [keyHex, keyHex + "0", keyHex + "gg", keyHex + "00", String(repeating: "0", count: 32) + cipher] {
            XCTAssertNil(WebVPNURLConverter.restore(root + "https/" + token + "/"))
        }
        XCTAssertNil(WebVPNURLConverter.restore(root))
        XCTAssertNil(WebVPNURLConverter.restore(root + "user/portal"))
    }

    func testDecryptedHostCannotInjectPathUserinfoOrItsOwnPort() {
        // Fixed AES-CFB ciphertext for evil.org/path, user@example.org and
        // example.org:8443, respectively. None is a valid standalone host.
        for cipher in ["f5e14890693f7a57311888b890", "e5e4448e07357051731885a9d65a3132", "f5ef4091373c6d1e711a8ef6c0017766"] {
            XCTAssertNil(WebVPNURLConverter.restore(root + "https/" + keyHex + cipher + "/"))
        }
    }

    func testUppercaseHexIsAcceptedAndRestoredURLCanBeConvertedAgain() throws {
        let source = "https://example.org:8443/path?a=1#part"
        let converted = try XCTUnwrap(WebVPNURLConverter.convert(source))
        let uppercase = root + "https-8443/" + (keyHex + "f5ef4091373c6d1e711a8e").uppercased() + "/path?a=1#part"
        XCTAssertEqual(WebVPNURLConverter.restore(uppercase)?.absoluteString, source)
        XCTAssertEqual(WebVPNURLConverter.convert(try XCTUnwrap(WebVPNURLConverter.restore(converted))), converted)
    }
}
