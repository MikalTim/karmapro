import Foundation
import XCTest
@testable import KarmaCore

final class GraphAndLicenseLogicTests: XCTestCase {

    // MARK: - ClassUsageScanner

    func testFindOccurrencesInJavaSampleReportsLinesAndSkipsOtherClasses() {
        let java = """
        public class Main {
            void run() {
                Widget w = new Widget(1);
                Widget g = new Widget<String>(2);
                Widget f = new WidgetFactory(3);
            }
        }
        """
        let url = URL(fileURLWithPath: "/tmp/Main.java")
        let hits = ClassUsageScanner.findOccurrences(of: "Widget", in: java, inFile: url)

        XCTAssertEqual(hits.map(\.line), [3, 4])
        XCTAssertTrue(hits[0].snippet.hasPrefix("new Widget(1)"))
        XCTAssertTrue(hits[1].snippet.hasPrefix("new Widget<String>(2)"))
        XCTAssertTrue(hits.allSatisfy { $0.fileURL == url })
    }

    func testFindOccurrencesInSwiftSampleFindsNoConstructionWithoutNew() {
        let swift = """
        let w = Widget(1)
        let v = Widget.make()
        """
        let hits = ClassUsageScanner.findOccurrences(of: "Widget", in: swift,
                                                     inFile: URL(fileURLWithPath: "/tmp/a.swift"))
        XCTAssertTrue(hits.isEmpty)
    }

    func testFindOccurrencesInCppSampleMatchesOnlyNewExpressions() {
        let cpp = """
        auto p = new Widget(3);
        Widget q(4);
        """
        let hits = ClassUsageScanner.findOccurrences(of: "Widget", in: cpp,
                                                     inFile: URL(fileURLWithPath: "/tmp/a.cpp"))
        XCTAssertEqual(hits.map(\.line), [1])
        XCTAssertTrue(hits[0].snippet.hasPrefix("new Widget(3)"))
    }

    func testScanInstantiationsWalksJavaAndCSharpAndSkipsTestDirectories() throws {
        let fixture = try ScanFixture([
            "src/Main.java": "class Main {\n    Object o = new Widget(1);\n}\n",
            "src/Tools.cs": "class Tools {\n\n    object o = new Widget(2);\n}\n",
            "src/test/Skip.java": "class Skip { Object o = new Widget(9); }\n",
            "src/readme.txt": "new Widget(7)\n",
        ])
        let hits = ClassUsageScanner.scanInstantiations(of: "Widget", in: fixture.root)

        let found = Set(hits.map { "\($0.fileURL.lastPathComponent):\($0.line)" })
        XCTAssertEqual(found, ["Main.java:2", "Tools.cs:3"])
    }

    // MARK: - ReachabilityPaths

    func testShortestPathPrefersFewestHops() {
        let edges = [("a", "b"), ("b", "c"), ("c", "d"), ("a", "d")]
        XCTAssertEqual(ReachabilityPaths.shortestPath(from: ["a"], to: "d", in: edges), ["a", "d"])
    }

    func testShortestPathFromMultipleSourcesUsesNearestSource() {
        let edges = [("x", "m"), ("m", "t"), ("y", "t")]
        XCTAssertEqual(ReachabilityPaths.shortestPath(from: ["x", "y"], to: "t", in: edges), ["y", "t"])
    }

    func testShortestPathTieBreakIsDeterministic() {
        let edges = [("a", "b"), ("a", "c"), ("b", "d"), ("c", "d")]
        XCTAssertEqual(ReachabilityPaths.shortestPath(from: ["a"], to: "d", in: edges), ["a", "b", "d"])
    }

    func testShortestPathReturnsNilWhenNoPathExists() {
        let edges = [("a", "b"), ("c", "d")]
        XCTAssertNil(ReachabilityPaths.shortestPath(from: ["a"], to: "d", in: edges))
    }

    func testShortestPathWithoutSourcesIsNil() {
        XCTAssertNil(ReachabilityPaths.shortestPath(from: [], to: "a", in: [("a", "b")]))
    }

    func testShortestPathToSourceItselfIsSingleNode() {
        XCTAssertEqual(ReachabilityPaths.shortestPath(from: ["a"], to: "a", in: []), ["a"])
    }

    // MARK: - LicenseScanner.analyzeLicenseText

    func testAnalyzeRecognisesMIT() {
        let a = LicenseScanner.analyzeLicenseText(
            "MIT License\n\nPermission is hereby granted, free of charge, to any person ...")
        XCTAssertEqual(a.name, "MIT License")
        XCTAssertTrue(a.commercialAllowed)
        XCTAssertEqual(a.conditions, "Permitted. Must include the original copyright notice and permission notice in all copies or substantial portions of the software.")
    }

    func testAnalyzeRecognisesApache2() {
        let a = LicenseScanner.analyzeLicenseText("Apache License\nVersion 2.0, January 2004")
        XCTAssertEqual(a.name, "Apache License 2.0")
        XCTAssertTrue(a.commercialAllowed)
    }

    func testAnalyzeRecognisesGPLv3AsConditional() {
        let a = LicenseScanner.analyzeLicenseText("GNU GENERAL PUBLIC LICENSE\nVersion 3, 29 June 2007")
        XCTAssertEqual(a.name, "GNU General Public License v3.0 (GPLv3)")
        XCTAssertTrue(a.commercialAllowed)
        XCTAssertTrue(a.conditions.hasPrefix("Conditionally Permitted."))
        XCTAssertTrue(a.conditions.contains("viral copyleft applies"))
    }

    func testAnalyzeUnknownTextIsNotCommerciallyAllowed() {
        let a = LicenseScanner.analyzeLicenseText("Proprietary terms: no use without a written agreement.")
        XCTAssertEqual(a.name, "Custom / Unrecognized Open Source / Proprietary")
        XCTAssertFalse(a.commercialAllowed)
        XCTAssertEqual(a.conditions, "Review license text carefully. Unless explicitly granted commercial rights, assume proprietary restrictions apply.")
    }

    // MARK: - LicenseScanner.report

    func testReportWithoutProjectFolder() {
        XCTAssertEqual(LicenseScanner.report(root: nil),
                       "No project folder currently open.\nPlease open a project using File > Open... to scan for licenses.")
    }

    func testReportFindsLicenseFileAndIgnoresManifest() throws {
        let mit = "MIT License\n\nPermission is hereby granted, free of charge, to any person obtaining a copy\n"
        let fixture = try ScanFixture([
            "LICENSE": mit,
            "package.json": "{ \"license\": \"MIT\" }\n",
        ])
        let report = LicenseScanner.report(root: fixture.root)

        XCTAssertTrue(report.hasPrefix("=== Project License & Commercial Use Audit ===\nScanned Root: \(fixture.root.path)\n\n"))
        XCTAssertTrue(report.contains("Found License File: LICENSE\n"))
        XCTAssertTrue(report.contains("• Detected License Type : MIT License\n"))
        XCTAssertTrue(report.contains("• Commercial Use Permitted? : YES ✅\n"))
        XCTAssertTrue(report.contains("License Snippet / Summary:\n" + mit))
        XCTAssertFalse(report.contains("package.json"))
        XCTAssertFalse(report.contains("No standard license files"))
    }

    func testReportWithoutLicenseFileStatesNoPermission() throws {
        let fixture = try ScanFixture(["package.json": "{}\n"])
        let report = LicenseScanner.report(root: fixture.root)

        XCTAssertTrue(report.contains("[-] No standard license files (LICENSE, LICENSE.md, COPYING) found in this project directory."))
        XCTAssertTrue(report.hasSuffix("You DO NOT have permission to use, copy, modify, or distribute this code commercially unless granted under a separate private agreement or contract with the author."))
    }
}
