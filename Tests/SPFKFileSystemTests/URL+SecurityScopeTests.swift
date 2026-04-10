// Copyright Ryan Francesconi. All Rights Reserved.

#if os(macOS) && !targetEnvironment(macCatalyst)
    import Foundation
    import SPFKBase
    @testable import SPFKFileSystem
    import SPFKTesting
    import Testing

    @Suite(.serialized)
    struct URLSecurityScopeTests {
        @Test func syncClosureReturnsValue() {
            let url = URL(fileURLWithPath: "/tmp/security-scope-test")
            let result = url.withSecurityScopedAccess { 42 }
            #expect(result == 42)
        }

        @Test func asyncClosureReturnsValue() async {
            let url = URL(fileURLWithPath: "/tmp/security-scope-test")
            let result = url.withSecurityScopedAccess { 99 }
            #expect(result == 99)
        }

        @Test func syncClosurePropagatesThrow() {
            let url = URL(fileURLWithPath: "/tmp/security-scope-test")
            struct Sentinel: Error {}
            #expect(throws: Sentinel.self) {
                try url.withSecurityScopedAccess { throw Sentinel() }
            }
        }

        @Test func syncClosureBodyExecutes() {
            let url = URL(fileURLWithPath: "/tmp/security-scope-test")
            var executed = false
            url.withSecurityScopedAccess { executed = true }
            #expect(executed)
        }

        @Test func asyncClosureBodyExecutes() async {
            let url = URL(fileURLWithPath: "/tmp/security-scope-test")
            var executed = false
            url.withSecurityScopedAccess { executed = true }
            #expect(executed)
        }
    }
#endif
