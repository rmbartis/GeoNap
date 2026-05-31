// SMTPService.swift
// Sends plain-text emails silently (no UI) via SMTP over implicit TLS (port 465).
// Used by AlarmManager to notify email contacts when an alarm fires.
//
// Setup: configure SMTP credentials in Settings → Email (SMTP).
// Gmail:   host = smtp.gmail.com,   port = 465, use an App Password
// Outlook: host = smtp.office365.com, port = 587 (note: use port 587 for Outlook)
// Yahoo:   host = smtp.mail.yahoo.com, port = 465, use an App Password

import Foundation
import Network

// MARK: - Configuration

struct SMTPConfig {
    var host:        String
    var port:        Int      // 465 = implicit TLS, 587 = STARTTLS (limited support)
    var username:    String   // usually the from-address
    var password:    String   // use an App Password for Gmail/Yahoo
    var fromAddress: String
    var fromName:    String

    /// True when all required fields are filled in.
    var isConfigured: Bool {
        !host.isEmpty && !username.isEmpty && !password.isEmpty && !fromAddress.isEmpty
    }

    /// Load from UserDefaults.
    static func load() -> SMTPConfig {
        let ud = UserDefaults.standard
        return SMTPConfig(
            host:        ud.string(forKey: "smtpHost")        ?? "",
            port:        ud.integer(forKey: "smtpPort") != 0
                             ? ud.integer(forKey: "smtpPort") : 465,
            username:    ud.string(forKey: "smtpUsername")    ?? "",
            password:    ud.string(forKey: "smtpPassword")    ?? "",
            fromAddress: ud.string(forKey: "smtpFromAddress") ?? "",
            fromName:    ud.string(forKey: "smtpFromName")    ?? "GeoNap"
        )
    }

    /// Persist to UserDefaults.
    func save() {
        let ud = UserDefaults.standard
        ud.set(host,        forKey: "smtpHost")
        ud.set(port,        forKey: "smtpPort")
        ud.set(username,    forKey: "smtpUsername")
        ud.set(password,    forKey: "smtpPassword")
        ud.set(fromAddress, forKey: "smtpFromAddress")
        ud.set(fromName,    forKey: "smtpFromName")
    }
}

// MARK: - Errors

enum SMTPError: Error, LocalizedError {
    case notConfigured
    case connectionFailed(String)
    case authFailed
    case sendFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:              return "SMTP is not configured. Add credentials in Settings → Email (SMTP)."
        case .connectionFailed(let msg):  return "SMTP connection failed: \(msg)"
        case .authFailed:                 return "SMTP authentication failed. Check username and password."
        case .sendFailed(let msg):        return "SMTP send failed: \(msg)"
        }
    }
}

// MARK: - Service

/// Sends a plain-text email to one or more recipients using SMTP over TLS.
/// Call from a background Task — this function is async and non-blocking on the main thread.
final class SMTPService {

    static let shared = SMTPService()
    private init() {}

    /// Send `body` to all `recipients` using the SMTP config stored in Settings.
    func send(to recipients: [String], subject: String, body: String) async throws {
        let config = SMTPConfig.load()
        guard config.isConfigured else { throw SMTPError.notConfigured }
        let client = SMTPClient(config: config)
        try await client.send(to: recipients, subject: subject, body: body)
    }
}

// MARK: - Client

private final class SMTPClient {

    private let config: SMTPConfig

    init(config: SMTPConfig) {
        self.config = config
    }

    func send(to recipients: [String], subject: String, body: String) async throws {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(config.host),
            port: NWEndpoint.Port(rawValue: UInt16(config.port))!
        )

        // Port 465 = implicit TLS from the start.
        // Port 587 = plain TCP then STARTTLS — we treat it as plain TCP here;
        //            full STARTTLS upgrade requires stream-level TLS which is
        //            handled by wrapping the command sequence with a TLS upgrade step.
        let params: NWParameters = config.port == 465 ? .tls : .tcp

        let conn = NWConnection(to: endpoint, using: params)

        // Bridge NWConnection callbacks → Swift async/await
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var finished = false
            func finish(_ result: Result<Void, Error>) {
                guard !finished else { return }
                finished = true
                conn.cancel()
                continuation.resume(with: result)
            }

            conn.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task {
                        do {
                            try await self.runSession(conn: conn,
                                                      recipients: recipients,
                                                      subject: subject,
                                                      body: body)
                            finish(.success(()))
                        } catch {
                            finish(.failure(error))
                        }
                    }
                case .failed(let err):
                    finish(.failure(SMTPError.connectionFailed(err.localizedDescription)))
                case .cancelled:
                    if !finished {
                        finish(.failure(SMTPError.connectionFailed("Connection cancelled")))
                    }
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .utility))
        }
    }

    // MARK: - SMTP protocol session

    private func runSession(conn: NWConnection,
                            recipients: [String],
                            subject: String,
                            body: String) async throws {
        // 1. Server greeting
        let greeting = try await readLine(conn)
        guard greeting.hasPrefix("220") else {
            throw SMTPError.connectionFailed("Unexpected greeting: \(greeting)")
        }

        // 2. EHLO
        try await writeLine("EHLO geonap\r\n", conn)
        _ = try await readMultiLine(conn)   // consume capability list

        // 3. AUTH LOGIN
        try await writeLine("AUTH LOGIN\r\n", conn)
        let r1 = try await readLine(conn)
        guard r1.hasPrefix("334") else { throw SMTPError.authFailed }

        let userB64 = Data(config.username.utf8).base64EncodedString()
        try await writeLine("\(userB64)\r\n", conn)
        let r2 = try await readLine(conn)
        guard r2.hasPrefix("334") else { throw SMTPError.authFailed }

        let passB64 = Data(config.password.utf8).base64EncodedString()
        try await writeLine("\(passB64)\r\n", conn)
        let r3 = try await readLine(conn)
        guard r3.hasPrefix("235") else { throw SMTPError.authFailed }

        // 4. MAIL FROM
        try await writeLine("MAIL FROM:<\(config.fromAddress)>\r\n", conn)
        let r4 = try await readLine(conn)
        guard r4.hasPrefix("250") else {
            throw SMTPError.sendFailed("MAIL FROM rejected: \(r4)")
        }

        // 5. RCPT TO — one per recipient
        for recipient in recipients {
            try await writeLine("RCPT TO:<\(recipient)>\r\n", conn)
            let r = try await readLine(conn)
            guard r.hasPrefix("250") else {
                throw SMTPError.sendFailed("RCPT TO rejected for \(recipient): \(r)")
            }
        }

        // 6. DATA
        try await writeLine("DATA\r\n", conn)
        let r5 = try await readLine(conn)
        guard r5.hasPrefix("354") else {
            throw SMTPError.sendFailed("DATA rejected: \(r5)")
        }

        // 7. Headers + body
        let toHeader   = recipients.joined(separator: ", ")
        let msgID      = UUID().uuidString.lowercased()
        let dateStr    = rfc2822Date()
        let safeFrom   = config.fromName.isEmpty ? config.fromAddress : config.fromName
        let message    = [
            "From: \(safeFrom) <\(config.fromAddress)>",
            "To: \(toHeader)",
            "Subject: \(subject)",
            "Date: \(dateStr)",
            "Message-ID: <\(msgID)@geonap.app>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "",
            body,
            "."
        ].joined(separator: "\r\n") + "\r\n"

        try await writeLine(message, conn)
        let r6 = try await readLine(conn)
        guard r6.hasPrefix("250") else {
            throw SMTPError.sendFailed("Message rejected: \(r6)")
        }

        // 8. QUIT
        try await writeLine("QUIT\r\n", conn)
    }

    // MARK: - Network I/O helpers

    private func writeLine(_ s: String, _ conn: NWConnection) async throws {
        let data = Data(s.utf8)
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { err in
                if let err { cont.resume(throwing: err) }
                else       { cont.resume() }
            })
        }
    }

    private func readLine(_ conn: NWConnection) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, err in
                if let err { cont.resume(throwing: err); return }
                let str = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                cont.resume(returning: str)
            }
        }
    }

    /// Read multi-line SMTP response (lines ending with "NNN-"); stops on "NNN ".
    private func readMultiLine(_ conn: NWConnection) async throws -> String {
        var full = ""
        while true {
            let chunk = try await readLine(conn)
            full += chunk
            // A line starting with "NNN " (space after code) signals the last line.
            let done = chunk.components(separatedBy: "\r\n").contains {
                $0.count >= 4 && $0[$0.index($0.startIndex, offsetBy: 3)] == " "
            }
            if done { break }
        }
        return full
    }

    // MARK: - Date helper

    private func rfc2822Date() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        return f.string(from: Date())
    }
}
