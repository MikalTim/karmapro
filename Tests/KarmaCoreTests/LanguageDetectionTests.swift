import XCTest
@testable import KarmaCore

/// One canonical tainted sink per supported language. Categories, severities
/// and engines are the ones the detector sources assign to these sinks.
final class LanguageDetectionTests: XCTestCase {

    func testC() throws {
        let fixture = try ScanFixture(["vuln.c": """
            #include <stdio.h>
            #include <string.h>
            #include <stdlib.h>
            int main(int argc, char **argv) {
                char buf[16];
                strcpy(buf, argv[1]);
                system(getenv("CMD"));
                printf(argv[2]);
                return 0;
            }
            """])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "vuln.c", line: 6, category: "Buffer Overflow", severity: .high, engine: "AST")
        XCTAssertFinding(findings, file: "vuln.c", line: 7, category: "Command Injection", severity: .high, engine: "AST")
        XCTAssertFinding(findings, file: "vuln.c", line: 8, category: "Format String", severity: .medium, engine: "AST")
    }

    func testObjectiveC() throws {
        let fixture = try ScanFixture(["V.m": """
            #import <Foundation/Foundation.h>
            @implementation V
            - (void)run:(NSString *)input {
                char buf[8];
                strcpy(buf, [input UTF8String]);
                system([input UTF8String]);
            }
            @end
            """])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "V.m", line: 5, category: "Buffer Overflow", severity: .high, engine: "AST")
        XCTAssertFinding(findings, file: "V.m", line: 6, category: "Command Injection", severity: .high, engine: "AST")
        XCTAssertEqual(findings.first { $0.line == 6 }?.function, "run:")
    }

    func testJava() throws {
        let fixture = try ScanFixture(["Cmd.java": """
            import javax.servlet.http.*;
            import java.sql.*;
            public class Cmd extends HttpServlet {
                public void doGet(HttpServletRequest request, HttpServletResponse response) throws Exception {
                    String host = request.getParameter("host");
                    Runtime.getRuntime().exec("ping " + host);
                    Connection c = DriverManager.getConnection("jdbc:x");
                    Statement s = c.createStatement();
                    s.executeQuery("SELECT * FROM u WHERE n='" + host + "'");
                }
            }
            """])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "Cmd.java", line: 6, category: "Command Injection", severity: .high, engine: "AST")
        XCTAssertFinding(findings, file: "Cmd.java", line: 9, category: "SQL Injection", severity: .high, engine: "AST")
    }

    func testCSharp() throws {
        let fixture = try ScanFixture(["Ctl.cs": """
            using System.Diagnostics;
            using System.Web;
            public class Ctl {
                public void Run(HttpRequest Request) {
                    string cmd = Request.QueryString["cmd"];
                    Process.Start(cmd);
                }
            }
            """])
        XCTAssertFinding(fixture.scan(), file: "Ctl.cs", line: 6, category: "Command Injection", severity: .high, engine: "AST")
    }

    func testKotlin() throws {
        let fixture = try ScanFixture(["Main.kt": """
            fun handle(request: HttpServletRequest) {
                val cmd = request.getParameter("cmd")
                Runtime.getRuntime().exec(cmd)
            }
            """])
        XCTAssertFinding(fixture.scan(), file: "Main.kt", line: 3, category: "Command Injection", severity: .high, engine: "AST")
    }

    func testPython() throws {
        let fixture = try ScanFixture(["app.py": """
            import os, subprocess
            from flask import request
            def run():
                cmd = request.args.get("cmd")
                os.system(cmd)
                return eval(request.args.get("x"))
            """])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "app.py", line: 5, category: "Command Injection", severity: .high, engine: "AST")
        XCTAssertFinding(findings, file: "app.py", line: 6, category: "Code Injection", severity: .high, engine: "AST")
    }

    func testRuby() throws {
        let fixture = try ScanFixture(["app.rb": """
            class C
              def run
                cmd = params[:cmd]
                system(cmd)
              end
            end
            """])
        XCTAssertFinding(fixture.scan(), file: "app.rb", line: 4, category: "Command Injection", severity: .high, engine: "AST")
    }

    func testGo() throws {
        let fixture = try ScanFixture(["main.go": """
            package main
            import ("net/http"; "os/exec")
            func handler(w http.ResponseWriter, r *http.Request) {
                cmd := r.URL.Query().Get("cmd")
                exec.Command("sh", "-c", cmd).Run()
            }
            """])
        XCTAssertFinding(fixture.scan(), file: "main.go", line: 5, category: "Command Injection", severity: .high, engine: "AST")
    }

    func testRust() throws {
        let fixture = try ScanFixture(["main.rs": """
            use std::process::Command;
            use std::env;
            fn main() {
                let arg = env::args().nth(1).unwrap();
                Command::new("sh").arg("-c").arg(arg).output().unwrap();
            }
            """])
        XCTAssertFinding(fixture.scan(), file: "main.rs", line: 5, category: "Command Injection", severity: .high, engine: "AST")
    }

    func testPHP() throws {
        let fixture = try ScanFixture(["index.php": """
            <?php
            function run() {
                $cmd = $_GET['cmd'];
                system($cmd);
                echo $_GET['name'];
            }
            """])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "index.php", line: 4, category: "Command Injection", severity: .high, engine: "AST")
        XCTAssertFinding(findings, file: "index.php", line: 5, category: "XSS (HTML Injection)", severity: .high, engine: "Heuristic")
    }

    func testSolidity() throws {
        let fixture = try ScanFixture(["W.sol": """
            pragma solidity ^0.8.0;
            contract W {
                mapping(address => uint) bal;
                address owner;
                function withdraw() public {
                    require(tx.origin == owner);
                    uint a = bal[msg.sender];
                    (bool ok, ) = msg.sender.call{value: a}("");
                    require(ok);
                    bal[msg.sender] = 0;
                }
            }
            """])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "W.sol", line: 6, category: "tx.origin Authorization", severity: .high, engine: "AST")
        XCTAssertFinding(findings, file: "W.sol", line: 8, category: "Reentrancy", severity: .high, engine: "AST")
    }

    func testJavaScript() throws {
        let fixture = try ScanFixture(["app.js": """
            const express = require('express');
            const app = express();
            app.get('/x', function handler(req, res) {
              const code = req.query.code;
              eval(code);
              res.send(req.query.name);
            });
            """])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "app.js", line: 5, category: "eval Injection", severity: .critical, engine: "AST")
        XCTAssertFinding(findings, file: "app.js", line: 6, category: "XSS (HTML Injection)", severity: .high, engine: "AST")
    }

    func testSwift() throws {
        let fixture = try ScanFixture([
            "A.swift": """
                import Foundation
                func run() {
                    let cmd = CommandLine.arguments[1]
                    system(cmd)
                }
                """,
            "B.swift": """
                import Foundation
                func go() {
                    let task = Process()
                    task.launchPath = CommandLine.arguments[1]
                    task.launch()
                }
                """,
        ])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "A.swift", line: 4, category: "Command Injection", severity: .critical, engine: "AST")
        XCTAssertFinding(findings, file: "B.swift", line: 4, category: "Command Injection", severity: .critical, engine: "AST")
        XCTAssertEqual(findings.first { $0.fileName == "A.swift" }?.taintPath, "CommandLine.arguments → system()")
    }

    func testHardcodedSecretAndWeakCrypto() throws {
        let fixture = try ScanFixture(["secrets.py": """
            import hashlib
            AWS_SECRET_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLEwJalrXUtnFEMI/K7MDENG"
            def h(x):
                return hashlib.md5(x).hexdigest()
            """])
        let findings = fixture.scan()
        XCTAssertFinding(findings, file: "secrets.py", line: 2, category: "Hardcoded Credential", severity: .high, engine: "Heuristic")
        XCTAssertFinding(findings, file: "secrets.py", line: 4, category: "Weak Cryptography", severity: .medium, engine: "AST")
    }
}
