import SwiftUI
import TipKit
import MultipeerConnectivity
import Combine

// MARK: - Model

struct Contact: Identifiable, Hashable, Codable {
    let id: UUID
    let name: String
    let relation: String
    var isGroup: Bool

    init(id: UUID = UUID(), name: String, relation: String, isGroup: Bool = false) {
        self.id = id
        self.name = name
        self.relation = relation
        self.isGroup = isGroup
    }
}

// MARK: - Sample Data

let sampleContacts: [Contact] = [
    Contact(name: "よしこ",   relation: "むすめ"),
    Contact(name: "みさき",   relation: "まご"),
    Contact(name: "たろう",   relation: "むすこ"),
    Contact(name: "けんいち", relation: "ともだち"),
]

// MARK: - TipKit

struct ContactTapTip: Tip {
    var title: Text {
        Text("ここを押してください")
            .fontWeight(.heavy)
    }
    var message: Text? {
        Text("名前を押すと、\n「電話」や「メッセージ」ができる画面に進みます。")
            .fontWeight(.bold)
            .foregroundColor(.primary)
    }
    var image: Image? {
        Image(systemName: "hand.point.up.left.fill")
    }
}

// MARK: - ContactRow

struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color.green, lineWidth: 2)
                    .frame(width: 56, height: 56)
                Image(systemName: contact.isGroup ? "person.3.fill" : "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26)
                    .foregroundStyle(.gray.opacity(0.5))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(contact.relation)
                    .foregroundStyle(.gray)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.gray.opacity(0.1))
        )
    }
}

// MARK: - ContactListView

struct ContactListView: View {
    @State private var contacts: [Contact] = sampleContacts
    @State private var showExchange = false
    let tapTip = ContactTapTip()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(contacts) { contact in
                        NavigationLink {
                            ContactDetailView(contact: contact)
                        } label: {
                            ContactRow(contact: contact)
                                .popoverTip(
                                    contact.name == contacts.first?.name ? tapTip : nil,
                                    arrowEdge: .top
                                )
                        }
                        .tint(.primary)
                    }
                }
                .padding()
            }
            .navigationTitle("れんらくさき")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showExchange = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.title2)
                    }
                    .accessibilityLabel("連絡先を交換する")
                }
            }
            .sheet(isPresented: $showExchange) {
                ContactExchangeView(contacts: $contacts)
            }
        }
    }
}

// MARK: - ContactDetailView

struct ContactDetailView: View {
    let contact: Contact
    @State private var showTalkAlert = false
    @State private var showCallAlert = false

    var body: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .stroke(Color.green, lineWidth: 4)
                    .frame(width: 130, height: 130)
                Image(systemName: contact.isGroup ? "person.3.fill" : "person.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 60)
                    .foregroundStyle(.gray.opacity(0.4))
            }
            VStack(spacing: 8) {
                Text(contact.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(contact.relation)
                    .font(.title3)
                    .foregroundStyle(.gray)
            }
            VStack(spacing: 16) {
                Button { showTalkAlert = true } label: {
                    Label("トーク", systemImage: "message.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                Button { showCallAlert = true } label: {
                    Label("でんわ", systemImage: "phone.fill")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 40)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .alert("トーク", isPresented: $showTalkAlert) {
            Button("OK") {}
        } message: {
            Text("\(contact.name)さんにメッセージを送ります")
        }
        .alert("でんわ", isPresented: $showCallAlert) {
            Button("かける") {}
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("\(contact.name)さんに電話をかけますか？")
        }
    }
}

// MARK: - Exchange Phase

enum ExchangePhase {
    case idle
    case searching
    case connecting
    case received(Contact)
    case failed(String)
}

// MARK: - NearbyContactManager
// @Published を使わず objectWillChange で通知（ExchangePhase が Equatable 非準拠のため）

class NearbyContactManager: NSObject, ObservableObject {

    var myContact: Contact?

    var phase: ExchangePhase = .idle {
        willSet { objectWillChange.send() }
    }
    var foundPeerNames: [String] = [] {
        willSet { objectWillChange.send() }
    }

    private let serviceType = "renraku-swap"
    private lazy var myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var allPeers: [MCPeerID] = []

    func startExchange() {
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser?.delegate = self
        advertiser?.startAdvertisingPeer()
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser?.delegate = self
        browser?.startBrowsingForPeers()
        phase = .searching
    }

    func stopExchange() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        allPeers = []
        foundPeerNames = []
        phase = .idle
    }

    func invite(peerName: String) {
        guard let session,
              let peer = allPeers.first(where: { $0.displayName == peerName }) else { return }
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 10)
        phase = .connecting
    }

    private func sendMyContact(to peer: MCPeerID) {
        guard let session,
              let contact = myContact,
              let data = try? JSONEncoder().encode(contact) else { return }
        try? session.send(data, toPeers: [peer], with: .reliable)
    }
}

extension NearbyContactManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            if state == .connected { self.sendMyContact(to: peerID) }
        }
    }
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let contact = try? JSONDecoder().decode(Contact.self, from: data) else { return }
        DispatchQueue.main.async {
            self.phase = .received(contact)
            self.stopExchange()
        }
    }
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension NearbyContactManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
        DispatchQueue.main.async { self.phase = .connecting }
    }
}

extension NearbyContactManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        DispatchQueue.main.async {
            if !self.allPeers.contains(peerID) {
                self.allPeers.append(peerID)
                self.foundPeerNames.append(peerID.displayName)
            }
        }
    }
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.allPeers.removeAll { $0 == peerID }
            self.foundPeerNames.removeAll { $0 == peerID.displayName }
        }
    }
}

// MARK: - ContactExchangeView

struct ContactExchangeView: View {
    @Binding var contacts: [Contact]
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = NearbyContactManager()
    @State private var myName: String = ""
    @State private var myRelation: String = ""
    @State private var showSuccess = false
    @State private var receivedContact: Contact?

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("あなたの情報")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    TextField("なまえ（例: はなこ）", text: $myName)
                        .font(.title3)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    TextField("続柄（例: むすめ）", text: $myRelation)
                        .font(.title3)
                        .padding()
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                Divider()
                stateView
                Spacer()

                if case .idle = manager.phase {
                    Button {
                        guard !myName.isEmpty else { return }
                        manager.myContact = Contact(
                            name: myName,
                            relation: myRelation.isEmpty ? "ともだち" : myRelation
                        )
                        manager.startExchange()
                    } label: {
                        Label("近くの人を探す", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(myName.isEmpty ? Color.gray : Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(myName.isEmpty)
                    .padding(.horizontal)
                } else if case .received = manager.phase {
                    EmptyView()
                } else {
                    Button { manager.stopExchange() } label: {
                        Text("キャンセル")
                            .font(.title3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color(.systemGray5))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .padding(.horizontal)
                }
            }
            .padding(.top, 24)
            .navigationTitle("連絡先を交換")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("とじる") { dismiss() }
                }
            }
            .onChange(of: manager.foundPeerNames) { _, _ in }  // 再描画トリガー
            .onReceive(manager.objectWillChange) { _ in }       // 再描画トリガー
            .alert("交換できました！", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                if let c = receivedContact {
                    Text("\(c.name)さん（\(c.relation)）が\n連絡先に追加されました")
                }
            }
            .onReceive(manager.objectWillChange) {
                if case .received(let contact) = manager.phase {
                    receivedContact = contact
                    contacts.append(contact)
                    showSuccess = true
                }
            }
        }
    }

    @ViewBuilder
    private var stateView: some View {
        switch manager.phase {
        case .idle:
            VStack(spacing: 12) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("iPhoneを近づけて\n連絡先を交換できます")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        case .searching:
            VStack(spacing: 16) {
                ProgressView().scaleEffect(2).tint(.green)
                Text("近くの人を探しています…")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if !manager.foundPeerNames.isEmpty {
                    VStack(spacing: 10) {
                        Text("見つかりました！").font(.headline)
                        ForEach(manager.foundPeerNames, id: \.self) { name in
                            Button { manager.invite(peerName: name) } label: {
                                HStack {
                                    Image(systemName: "person.fill")
                                    Text(name).font(.title3.bold())
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
        case .connecting:
            VStack(spacing: 16) {
                ProgressView().scaleEffect(2).tint(.blue)
                Text("交換中…").font(.title3).foregroundStyle(.secondary)
            }
        case .received:
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.green)
                Text("交換できました！").font(.title2.bold())
            }
        case .failed(let msg):
            VStack(spacing: 12) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)
                Text(msg).font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}

// MARK: - ContentView（TestApp.swift の @main から呼ばれる）

struct ContentView: View {
    var body: some View {
        ContactListView()
            .task {
                try? Tips.configure([
                    .displayFrequency(.immediate),
                    .datastoreLocation(.applicationDefault)
                ])
            }
    }
}

// MARK: - Preview

#Preview("連絡先一覧") { ContactListView() }
#Preview("よしこ 詳細") {
    NavigationStack { ContactDetailView(contact: sampleContacts[0]) }
}
#Preview("連絡先交換") {
    ContactExchangeView(contacts: .constant(sampleContacts))
}
