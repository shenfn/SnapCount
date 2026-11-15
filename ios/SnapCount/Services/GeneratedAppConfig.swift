import Foundation

enum GeneratedAppConfig {
    // Local simulator defaults. CI still overwrites this file from secrets
    // before archive builds. The anon key is the public client key already
    // shipped in the PWA bundle, never a service-role credential.
    static let supabaseURL = "https://api.snapflow.me"
    static let supabaseFunctionsURL = "https://api.snapflow.me"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlnYmdocmhzZGFvbHhsamdpaXNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzczNjUyMzIsImV4cCI6MjA5Mjk0MTIzMn0.4wHUISstAFApLOnAn2hZdstWRtBmAjjGC_KetsUdmbA"
    static let shortcutTemplateURL = ""
    static let photoShortcutTemplateURL = ""
    static let screenshotShortcutTemplateURL = ""
}
