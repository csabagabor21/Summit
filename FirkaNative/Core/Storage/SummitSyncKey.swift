import CryptoKit
import Foundation

/// SummitSync kulcsképzés JWT-független része (csak Foundation +
/// CryptoKit). Külön fájlban, hogy a logika az app-célpont
/// Firebase-függései nélkül, önállóan is végrehajtható legyen.
enum SummitSyncKey {
    static let versionTag = "summit-sync-v1"
    static let minPassphraseLength = 8

    /// Helyi (nem JWT) tokenek stabil kulcsa. A tesztfiók fix tokenje
    /// minden eszközön azonos, így a jelmondattal együtt ugyanúgy
    /// kitalálhatatlan doc-ID-t ad, mint a JWT-sub.
    /// Kifejezetten csak a review-fiók kap kulcsot — a demo szinkron
    /// szándékosan nem létezik (a Beállítások UI-kapu mögött marad,
    /// és itt sem kap kulcsot).
    static func localStableKey(from accessToken: String) -> String? {
        let t = accessToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard t == AppUser.reviewerToken else { return nil }
        return "local:summitreview"
    }

    /// Doc-ID a stabil kulcsból + jelmondatból. Nil, ha nincs stabil
    /// kulcs, vagy a jelmondat túl rövid.
    static func syncId(stableKey: String?, passphrase: String) -> String? {
        guard let stable = stableKey, !stable.isEmpty,
              passphrase.count >= minPassphraseLength else { return nil }
        let input = "\(versionTag)\n\(stable)\n\(passphrase)"
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Mezőszintű last-writer-wins: a távoli nyer, ha bélyege újabb,
    /// mint a helyi szerkesztés (piszkos-mező idő, különben az utolsó
    /// ismert bélyeg). Egyenlőnél a helyi marad — a saját push
    /// visszhangja nem minősül újdonságnak.
    static func remoteWins(remoteTs: Date?, dirtyAt: Date?, localTs: Date) -> Bool {
        guard let r = remoteTs else { return false }
        if let d = dirtyAt { return r > d }
        return r > localTs
    }
}
