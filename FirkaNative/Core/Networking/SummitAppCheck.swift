import Foundation
import DeviceCheck
import os
import FirebaseCore
import FirebaseAppCheck

/// Firebase App Check: minden Summit-backend hívás (Firestore REST, a
/// Live Activity worker, az AI-proxy) igazolja, hogy a kérés a valódi,
/// módosítatlan appból jön — a publikus API-kulcs egymagában így nem
/// elég a backend eléréséhez (a repo nyílt forrású, a kulcs nem titok).
///
/// - Release: App Attest (Secure Enclave); ahol nem támogatott vagy hibázik
///   (pl. régebbi Mac, hiányzó App Attest capability), ott DeviceCheck.
/// - Debug: debug-provider — az első futáskor a konzolba írt debug tokent
///   a Firebase konzolban (App Check → Apps → Manage debug tokens) kell
///   regisztrálni, különben a szimulátoros build kérései enforce után
///   elutasítódnak.
///
/// Az SDK a Firestore-listenerre magától teszi rá a tokent; a kézi REST-
/// hívásokhoz az `attach(to:)` adja hozzá a fejlécet.
enum SummitAppCheck {
    static let header = "X-Firebase-AppCheck"

    /// A FirebaseApp.configure() ELŐTT kell hívni (az SDK csak akkor
    /// használja a gyárat, ha a konfiguráláskor már be van állítva).
    static func installProviderFactory() {
        AppCheck.setAppCheckProviderFactory(ProviderFactory())
    }

    /// Érvényes App Check token, vagy nil (nincs Firebase-konfig, nincs
    /// net, az attesztáció hibázott, vagy 10 mp alatt nem jött válasz).
    /// Nil esetén a hívó fejléc nélkül küld: a backend a bevezetés első
    /// szakaszában (monitor mód) ezt még elfogadja, enforce után nem.
    static func token() async -> String? {
        guard FirebaseApp.app() != nil else { return nil }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(cont)
            AppCheck.appCheck().token(forcingRefresh: false) { token, error in
                if let error {
                    log.error("App Check token hiba: \(error.localizedDescription, privacy: .public)")
                }
                once.resume(token?.token)
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) {
                once.resume(nil)
            }
        }
    }

    private static let log = Logger(subsystem: "hu.flint.summit", category: "appcheck")

    /// A continuation pontosan egyszer folytatódik: vagy a token jön meg,
    /// vagy a 10 mp-es időkorlát jár le — amelyik előbb.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<String?, Never>?
        init(_ cont: CheckedContinuation<String?, Never>) { self.cont = cont }
        func resume(_ value: String?) {
            lock.lock()
            let c = cont
            cont = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }

    /// A kérésre ráteszi az App Check fejlécet, ha van token.
    static func attach(to request: inout URLRequest) async {
        if let t = await token() {
            request.setValue(t, forHTTPHeaderField: header)
        }
    }

    private final class ProviderFactory: NSObject, AppCheckProviderFactory {
        func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
            #if DEBUG
            return AppCheckDebugProvider(app: app)
            #else
            let attest = DCAppAttestService.shared.isSupported ? AppAttestProvider(app: app) : nil
            return AttestWithFallbackProvider(attest: attest, deviceCheck: DeviceCheckProvider(app: app))
            #endif
        }
    }

    /// App Attest, és ha az nem ad tokent (nem támogatott eszköz, hiányzó
    /// App Attest capability a profilban, Apple-oldali hiba), DeviceCheck —
    /// így egy attesztációs hiba nem vágja el az appot a backendtől.
    private final class AttestWithFallbackProvider: NSObject, AppCheckProvider {
        private let attest: AppAttestProvider?
        private let deviceCheck: DeviceCheckProvider?

        init(attest: AppAttestProvider?, deviceCheck: DeviceCheckProvider?) {
            self.attest = attest
            self.deviceCheck = deviceCheck
        }

        func getToken(completion handler: @escaping (AppCheckToken?, Error?) -> Void) {
            guard let attest else { fallback(error: nil, handler); return }
            attest.getToken { token, error in
                if let token { handler(token, nil) } else { self.fallback(error: error, handler) }
            }
        }

        private func fallback(error: Error?, _ handler: @escaping (AppCheckToken?, Error?) -> Void) {
            if let error {
                log.error("App Attest hiba, DeviceCheck jön: \(error.localizedDescription, privacy: .public)")
            }
            guard let deviceCheck else {
                handler(nil, error ?? NSError(domain: "SummitAppCheck", code: 1,
                                              userInfo: [NSLocalizedDescriptionKey: "Nincs App Check provider"]))
                return
            }
            deviceCheck.getToken(completion: handler)
        }
    }
}
