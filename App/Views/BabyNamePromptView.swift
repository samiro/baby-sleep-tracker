import SwiftUI

public struct BabyNamePromptView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var babyName: String = ""
    private let onComplete: (() -> Void)?

    public init(onComplete: (() -> Void)? = nil) {
        self.onComplete = onComplete
    }

    private var trimmedName: String {
        babyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                // Decorative Icon
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.12))
                        .frame(width: 96, height: 96)

                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(.indigo)
                }

                // Headers
                VStack(spacing: 8) {
                    Text("¡Bienvenido!")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)

                    Text("¿Cómo se llama tu bebé?")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Text("Personaliza la pantalla principal con el nombre de tu bebé para dar seguimiento a sus horarios de sueño.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Text field input
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Nombre del bebé (ej. Leo, Sofía)", text: $babyName)
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .onSubmit {
                            saveAndDismiss()
                        }

                    Text("Podrás editar o cambiar este nombre en cualquier momento desde la sección de Ajustes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Action Buttons
                VStack(spacing: 12) {
                    Button {
                        saveAndDismiss()
                    } label: {
                        Text(trimmedName.isEmpty ? "Continuar con nombre por defecto" : "Guardar nombre")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .foregroundColor(.white)
                            .background(Color.indigo)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if !trimmedName.isEmpty {
                        Button {
                            skipAndDismiss()
                        } label: {
                            Text("Usar nombre por defecto (\(BabyProfileManager.defaultAppName))")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Omitir") {
                        skipAndDismiss()
                    }
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                }
            }
            .onDisappear {
                if !BabyProfileManager.shared.hasPromptedBabyName {
                    let nameToSave = trimmedName.isEmpty ? nil : trimmedName
                    BabyProfileManager.shared.completeOnboarding(withBabyName: nameToSave)
                    onComplete?()
                }
            }
        }
    }

    private func saveAndDismiss() {
        let nameToSave = trimmedName.isEmpty ? nil : trimmedName
        BabyProfileManager.shared.completeOnboarding(withBabyName: nameToSave)
        onComplete?()
        dismiss()
    }

    private func skipAndDismiss() {
        BabyProfileManager.shared.completeOnboarding(withBabyName: nil)
        onComplete?()
        dismiss()
    }
}
