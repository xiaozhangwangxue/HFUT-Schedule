import Foundation

/// Public anonymous-role configuration from upstream; user sessions are stored separately in Keychain.
enum SupabasePublicConfiguration {
    static let baseURL = URL(string: "https://uadgxvstybecnhqemxvj.supabase.co/")!
    static let anonymousKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVhZGd4dnN0eWJlY25ocWVteHZqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDQ2Mzc2MjEsImV4cCI6MjA2MDIxMzYyMX0.o0lIRgVGoadxyeq4Hj3XNO0R9Aop9ZKDDvVCLkeSJJU"
}
