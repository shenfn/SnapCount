import Foundation

struct PersistedDashboardSnapshot: Codable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let userId: String
    let savedAt: Date
    let todayCount: Int
    let pendingCount: Int
    let monthCount: Int
    let monthExpense: Double
    let monthIncome: Double
    let todayExpense: Double
    let todayIncome: Double
    let dailySummaries: [DailySummary]
    let dayRecordGroups: [DayRecordGroup]
    let recentRecords: [RecordSummary]
    let stagingRecords: [StagingRecord]
    let pendingExpenses: [PendingExpense]
    let domains: [Domain]

    init(userId: String, snapshot: DashboardSnapshot, savedAt: Date = Date()) {
        schemaVersion = Self.currentSchemaVersion; self.userId = userId; self.savedAt = savedAt
        todayCount = snapshot.todayCount; pendingCount = snapshot.pendingCount; monthCount = snapshot.monthCount
        monthExpense = snapshot.monthExpense; monthIncome = snapshot.monthIncome; todayExpense = snapshot.todayExpense; todayIncome = snapshot.todayIncome
        dailySummaries = snapshot.dailySummaries.map(DailySummary.init); dayRecordGroups = snapshot.dayRecordGroups.map(DayRecordGroup.init)
        recentRecords = snapshot.recentRecords.map(RecordSummary.init); stagingRecords = snapshot.stagingRecords.map(StagingRecord.init)
        pendingExpenses = snapshot.pendingExpenses.map(PendingExpense.init); domains = snapshot.domains.map(Domain.init)
    }

    var dashboardSnapshot: DashboardSnapshot {
        DashboardSnapshot(todayCount: todayCount, pendingCount: pendingCount, monthCount: monthCount, monthExpense: monthExpense, monthIncome: monthIncome, todayExpense: todayExpense, todayIncome: todayIncome, dailySummaries: dailySummaries.map(\.native), dayRecordGroups: dayRecordGroups.map(\.native), loadWarnings: [], recordDetails: [:], recentRecords: recentRecords.map(\.native), stagingRecords: stagingRecords.map(\.native), pendingExpenses: pendingExpenses.map(\.native), domains: domains.map(\.native))
    }

    struct DailySummary: Codable { let dateKey: String; let expense: Double; let income: Double; let pendingCount: Int; let recordCount: Int; init(_ value: NativeDailySummary) { dateKey=value.dateKey; expense=value.expense; income=value.income; pendingCount=value.pendingCount; recordCount=value.recordCount }; var native: NativeDailySummary { NativeDailySummary(dateKey:dateKey,expense:expense,income:income,pendingCount:pendingCount,recordCount:recordCount) } }
    struct DayRecord: Codable { let id:String; let reference:String; let dateKey:String; let kind:String; let domainKey:String?; let title:String; let subtitle:String; let value:String; let timeLabel:String?; let systemImage:String; init(_ item:NativeDayRecord){id=item.id;reference=item.reference;dateKey=item.dateKey;kind=item.kind.rawValue;domainKey=item.domainKey;title=item.title;subtitle=item.subtitle;value=item.value;timeLabel=item.timeLabel;systemImage=item.systemImage}; var native:NativeDayRecord?{guard let kind=NativeDayRecordKind(rawValue:kind) else{return nil};return NativeDayRecord(id:id,reference:reference,dateKey:dateKey,kind:kind,domainKey:domainKey,title:title,subtitle:subtitle,value:value,timeLabel:timeLabel,systemImage:systemImage)} }
    struct DayRecordGroup: Codable { let dateKey:String; let records:[DayRecord]; init(_ value:NativeDayRecordGroup){dateKey=value.dateKey;records=value.records.map(DayRecord.init)}; var native:NativeDayRecordGroup{NativeDayRecordGroup(dateKey:dateKey,records:records.compactMap(\.native))} }
    struct RecordSummary: Codable { let id:String;let title:String;let subtitle:String;let value:String;let systemImage:String;init(_ item:NativeRecordSummary){id=item.id;title=item.title;subtitle=item.subtitle;value=item.value;systemImage=item.systemImage};var native:NativeRecordSummary{NativeRecordSummary(id:id,title:title,subtitle:subtitle,value:value,systemImage:systemImage)} }
    struct PendingExpense: Codable { let id:String;let title:String;let amount:Double;let dateKey:String;let reference:String;let imagePath:String?;let occurredAtLabel:String?;let createdAtLabel:String?;init(_ item:NativePendingExpense){id=item.id;title=item.title;amount=item.amount;dateKey=item.dateKey;reference=item.reference;imagePath=item.imagePath;occurredAtLabel=item.occurredAtLabel;createdAtLabel=item.createdAtLabel};var native:NativePendingExpense{NativePendingExpense(id:id,title:title,amount:amount,dateKey:dateKey,reference:reference,imagePath:imagePath,occurredAtLabel:occurredAtLabel,createdAtLabel:createdAtLabel ?? "最近上传")} }
    struct Domain: Codable { let id:String;let name:String;let description:String;let icon:String;let isSystem:Bool;let schema:[String:AnyCodable];let display:[String:AnyCodable];let recordCount:Int;init(_ item:NativeDomainDefinition){id=item.id;name=item.name;description=item.description;icon=item.icon;isSystem=item.isSystem;schema=item.schema;display=item.display;recordCount=item.recordCount};var native:NativeDomainDefinition{NativeDomainDefinition(id:id,name:name,description:description,icon:icon,isSystem:isSystem,schema:schema,display:display,recordCount:recordCount)} }
    struct StagingRecord: Codable { let id:String;let dateKey:String;let title:String;let summary:String;let status:String;let statusLabel:String;let recordTypeLabel:String;let createdAtLabel:String;let occurredAtLabel:String?;let confidencePercent:Int?;let lastErrorMessage:String?;let retryCount:Int;let systemImage:String;let imagePath:String?;let recordType:String;let domainKey:String?;let domainName:String?;let extracted:[String:AnyCodable];let companionMessage:String?;let targetRecordId:String?;let imageHash:String?;init(_ item:NativeStagingRecord){id=item.id;dateKey=item.dateKey;title=item.title;summary=item.summary;status=item.status;statusLabel=item.statusLabel;recordTypeLabel=item.recordTypeLabel;createdAtLabel=item.createdAtLabel;occurredAtLabel=item.occurredAtLabel;confidencePercent=item.confidencePercent;lastErrorMessage=item.lastErrorMessage;retryCount=item.retryCount;systemImage=item.systemImage;imagePath=item.imagePath;recordType=item.recordType;domainKey=item.domainKey;domainName=item.domainName;extracted=item.extracted;companionMessage=item.companionMessage;targetRecordId=item.targetRecordId;imageHash=item.imageHash};var native:NativeStagingRecord{NativeStagingRecord(id:id,dateKey:dateKey,title:title,summary:summary,status:status,statusLabel:statusLabel,recordTypeLabel:recordTypeLabel,createdAtLabel:createdAtLabel,occurredAtLabel:occurredAtLabel,confidencePercent:confidencePercent,lastErrorMessage:lastErrorMessage,retryCount:retryCount,systemImage:systemImage,imagePath:imagePath,imageURL:nil,imageLoadError:false,recordType:recordType,domainKey:domainKey,domainName:domainName,extracted:extracted,companionMessage:companionMessage,targetRecordId:targetRecordId,imageHash:imageHash)} }
}

protocol DashboardSnapshotStoreProtocol { func load(userId:String)throws->PersistedDashboardSnapshot?; func save(_ snapshot:DashboardSnapshot,userId:String)throws; func remove(userId:String)throws }

final class DashboardSnapshotStore: DashboardSnapshotStoreProtocol {
    private let directory:URL; private let encoder=JSONEncoder(); private let decoder=JSONDecoder()
    init(directory:URL?=nil){self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("DashboardSnapshots",isDirectory:true);encoder.dateEncodingStrategy = .iso8601;decoder.dateDecodingStrategy = .iso8601}
    func load(userId:String)throws->PersistedDashboardSnapshot?{let url=fileURL(userId:userId);guard FileManager.default.fileExists(atPath:url.path)else{return nil};let value=try decoder.decode(PersistedDashboardSnapshot.self,from:Data(contentsOf:url));guard value.schemaVersion==PersistedDashboardSnapshot.currentSchemaVersion,value.userId==userId else{return nil};return value}
    func save(_ snapshot:DashboardSnapshot,userId:String)throws{try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true);let data=try encoder.encode(PersistedDashboardSnapshot(userId:userId,snapshot:snapshot));try data.write(to:fileURL(userId:userId),options:.atomic)}
    func remove(userId:String)throws{let url=fileURL(userId:userId);if FileManager.default.fileExists(atPath:url.path){try FileManager.default.removeItem(at:url)}}
    private func fileURL(userId:String)->URL{directory.appendingPathComponent("dashboard-\(userId.replacingOccurrences(of:"/",with:"_")).json")}
}
