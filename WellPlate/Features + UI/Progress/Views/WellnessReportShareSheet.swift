import SwiftUI

struct WellnessReportShareSheet: View {
    let reportData: WellnessReportData
    let foodLogs: [FoodLogEntry]
    let stressReadings: [StressReading]
    let wellnessLogs: [WellnessDayLog]

    @State private var imageURL: URL? = nil
    @State private var csvURL: URL? = nil
    @State private var isRendering = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if isRendering {
                    ProgressView("Generating report…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Preview card — scale to fit screen width
                            let screenW = UIScreen.main.bounds.width - 40
                            let scale = screenW / 390
                            WellnessReportView(data: reportData)
                                .scaleEffect(scale, anchor: .top)
                                .frame(width: 390 * scale, height: 340 * scale)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .appShadow(radius: 16, y: 6)
                                .padding(.horizontal, 20)

                            // Share buttons
                            VStack(spacing: 12) {
                                if let url = imageURL {
                                    ShareLink(
                                        item: url,
                                        preview: SharePreview("WellPlate Weekly Report")
                                    ) {
                                        Label("Share as Image", systemImage: "photo")
                                            .font(.r(.body, .semibold))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(AppColors.brand)
                                            .foregroundColor(.white)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                }

                                if let url = csvURL {
                                    ShareLink(
                                        item: url,
                                        preview: SharePreview("WellPlate Weekly Data.csv")
                                    ) {
                                        Label("Export as CSV", systemImage: "tablecells")
                                            .font(.r(.body, .medium))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 14)
                                            .background(Color(.secondarySystemBackground))
                                            .foregroundColor(AppColors.textPrimary)
                                            .clipShape(RoundedRectangle(cornerRadius: 14))
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Weekly Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.r(.body, .semibold))
                        .foregroundColor(AppColors.brand)
                }
            }
        }
        .presentationDetents([.large])
        .task {
            // Render image → write to temp JPEG (only set imageURL if write succeeds)
            if let uiImage = await WellnessReportGenerator.renderImage(data: reportData),
               let jpegData = uiImage.jpegData(compressionQuality: 0.88) {
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("WellPlate_Weekly_Report.jpg")
                if (try? jpegData.write(to: url)) != nil {
                    imageURL = url
                }
            }

            // Generate CSV → write to temp .csv file (only set csvURL if write succeeds)
            let csvData = WellnessReportGenerator.generateCSV(
                foodLogs: foodLogs,
                stressReadings: stressReadings,
                wellnessLogs: wellnessLogs
            )
            let csvFileURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("WellPlate_Weekly_Data.csv")
            if (try? csvData.write(to: csvFileURL)) != nil {
                csvURL = csvFileURL
            }

            isRendering = false
        }
        .onDisappear {
            if let url = imageURL { try? FileManager.default.removeItem(at: url) }
            if let url = csvURL   { try? FileManager.default.removeItem(at: url) }
        }
    }
}
