import Foundation

/// User-facing legal copy + version, sourced from the regulatory-affairs DRAFT at
/// `docs/legal/humans-terms-and-disclaimer.md` (Part 1 — in-app short version).
///
/// ⚠️ DRAFT — NOT FINAL. That document states a UAE-qualified lawyer must review enforceability and the
/// CEO signs off before it ships. This file wires the drafted SHORT text so the consent gate + disclaimer
/// placements are real and testable; the exact wording and `termsVersion` are provisional until legal +
/// CEO approval. Bump `termsVersion` when the terms materially change to re-prompt accepted users.
enum Legal {
    /// Bump on a material terms change → `ConsentRecord.accepted` goes false → users re-prompted.
    static let termsVersion = 1

    /// Where the full binding Terms live (placeholder — final URL owned by legal/DPO before ship).
    static let fullTermsURL = URL(string: "https://humans.app/terms")

    // A-short · Wellness, not medical advice
    static let wellnessNotMedical =
        "HUMANS is a fitness & wellness app — not medical advice. It doesn't diagnose, treat, or prevent any condition, and it isn't a substitute for a doctor. Results aren't guaranteed and vary by person."

    // B-short · Check with a professional first
    static let checkProfessional =
        "Talk to your doctor before starting. Get medical clearance before beginning any exercise or nutrition plan — especially if you're pregnant, older, recovering from illness or injury, or have any health condition or symptoms (chest pain, dizziness, breathlessness). If something hurts or feels wrong, stop and seek advice."

    // C-short · You're in control (assumption of risk)
    static let assumptionOfRisk =
        "Exercise carries risk, and you take part voluntarily. You decide whether any suggested workout, intensity, or meal fits you today. Work within your own limits, warm up, use good form, and stop if you feel unwell. You're responsible for your own choices while using HUMANS."

    // D-short · About Physical Age
    static let aboutPhysicalAge =
        "Physical Age is a motivational fitness estimate from your wearable data — not your real, biological, or clinical age, and not a prediction of how long you'll live. It's there to show trends and keep you motivated, nothing more."

    // First-run consent gate intro
    static let consentIntro =
        "To use your weekly programme and Physical Age, please confirm you've read and agree to the Health Disclaimer & Terms of Use, and that you take part in physical activity at your own risk."

    static let consentCheckbox = "I've read and I agree to the Health Disclaimer & Terms of Use"

    // Short one-liners for inline placements (kept wellness-framed).
    static let placementShort =
        "Wellness estimate, not medical advice. Talk to your doctor before starting, and stop if you feel unwell."

    // Extra-prominent line the first time a higher-intensity session appears.
    static let intensityFirstTime =
        "Higher-intensity training carries more risk. Only push if you're well and cleared to — warm up, keep good form, and stop if anything feels wrong. This is general wellness guidance, not medical advice."
}
