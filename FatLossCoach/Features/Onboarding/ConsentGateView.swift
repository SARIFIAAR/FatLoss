import SwiftUI

/// First-run BLOCKING consent gate: the user must read + agree to the health disclaimer, assumption of
/// risk, and Terms of Use before using the app. Unchecked box by default, no skip; "Continue" stays
/// disabled until the box is ticked. Acceptance is recorded version-stamped + timestamped by the caller
/// (`Store.acceptConsent`) and cloud-mirrors for provability. Re-shown on a material terms-version change.
///
/// Copy is the DRAFT short-form from `docs/legal/humans-terms-and-disclaimer.md` (Part 1), surfaced via
/// `Legal.*`. ⚠️ That text is pending UAE-lawyer review + CEO sign-off before ship — wiring, not final law.
struct ConsentGateView: View {
    let onAccept: () -> Void
    @State private var agreed = false
    @State private var showFullTerms = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("Before you start")
                            .font(Theme.titleL).foregroundStyle(Theme.text).padding(.top, 8)

                        Text(Legal.consentIntro)
                            .font(.system(size: 14)).foregroundStyle(Theme.muted).lineSpacing(4)

                        clause("Wellness, not medical advice", Legal.wellnessNotMedical)
                        clause("Check with a professional first", Legal.checkProfessional)
                        clause("You're in control", Legal.assumptionOfRisk)
                        clause("About Physical Age", Legal.aboutPhysicalAge)

                        Button {
                            showFullTerms = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.text").font(.system(size: 13))
                                Text("Read the full Health Disclaimer & Terms")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(Theme.primary)
                        }
                        .padding(.top, 2)
                    }
                    .padding(20)
                }

                // Sticky accept row.
                VStack(spacing: 14) {
                    Button {
                        agreed.toggle()
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: agreed ? "checkmark.square.fill" : "square")
                                .font(.system(size: 22)).foregroundStyle(agreed ? Theme.primary : Theme.muted)
                            Text(Legal.consentCheckbox)
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)

                    Button("Continue") { if agreed { onAccept() } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(!agreed)
                        .opacity(agreed ? 1 : 0.5)
                }
                .padding(20)
                .background(Theme.card.ignoresSafeArea(edges: .bottom))
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showFullTerms) { FullTermsView() }
    }

    private func clause(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
            Text(body).font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// Scrollable full-terms sheet. For now it presents the short clauses in full plus a pointer to the
/// binding online Terms (final URL owned by legal/DPO). Reused from Settings via a persistent link.
struct FullTermsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Health Disclaimer, Assumption of Risk & Terms of Use")
                        .font(.system(size: 18, weight: .heavy)).foregroundStyle(Theme.text)
                    Text("HUMANS is a general wellness & fitness app. Draft in-app summary — the full binding Terms are linked below.")
                        .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    Group {
                        para("Wellness, not medical advice", Legal.wellnessNotMedical)
                        para("Check with a professional first", Legal.checkProfessional)
                        para("Assumption of risk & your responsibility", Legal.assumptionOfRisk)
                        para("About Physical Age", Legal.aboutPhysicalAge)
                    }
                    if let url = Legal.fullTermsURL {
                        Link(destination: url) {
                            Text("Read the full Terms of Use").font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.primary)
                        }.padding(.top, 4)
                    }
                }
                .padding(20)
            }
            .background(Theme.bg)
            .navigationTitle("Terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button { dismiss() } label: { Image(systemName: "xmark") } } }
        }
        .preferredColorScheme(.dark)
    }
    private func para(_ t: String, _ b: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(t).font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.text)
            Text(b).font(.system(size: 13)).foregroundStyle(Theme.muted).lineSpacing(4)
        }
    }
}
