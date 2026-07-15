import Foundation

struct NativeInboxRoute: Hashable {
    let recordId: String
}

struct NativeRecordRoute: Hashable {
    let reference: String
}

struct NativeDomainRoute: Hashable {
    let domainId: String
}

struct NativeAccountRoute: Hashable {
    let accountId: String
}
