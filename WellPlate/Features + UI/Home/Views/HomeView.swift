import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: HomeViewModel
    @StateObject private var narrator = NutritionNarratorService()

    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var showProfile = false
    @State private var showProgressInsights = false
    @State private var showStreak = false
    @State private var isGoalsExpanded = false
    @FocusState private var isTextEditorFocused: Bool
    @State private var scrollOffset: CGFloat = 0
    @State private var dragOffset: CGFloat = 0

    @Query private var foodLogs: [FoodLogEntry]

    init(viewModel: HomeViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)

        let sixtyDaysAgo = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? Date()
        let predicate = #Predicate<FoodLogEntry> { entry in
            entry.day >= sixtyDaysAgo
        }
        _foodLogs = Query(filter: predicate, sort: \.createdAt, order: .reverse)
    }

    private var aggregatedNutrition: NutritionalInfo? {
        let targetDay = Calendar.current.startOfDay(for: selectedDate)

        let filteredLogs = foodLogs.filter { $0.day == targetDay }
        guard !filteredLogs.isEmpty else { return nil }

        let totalCalories = min(
            filteredLogs.reduce(0) { $0 + $1.calories },
            999999
        )
        let totalProtein = filteredLogs.reduce(0.0) { $0 + $1.protein }
        let totalCarbs = filteredLogs.reduce(0.0) { $0 + $1.carbs }
        let totalFat = filteredLogs.reduce(0.0) { $0 + $1.fat }
        let totalFiber = filteredLogs.reduce(0.0) { $0 + $1.fiber }

        return NutritionalInfo(
            foodName: "\(filteredLogs.count) item\(filteredLogs.count == 1 ? "" : "s")",
            servingSize: nil,
            calories: totalCalories,
            protein: totalProtein,
            carbs: totalCarbs,
            fat: totalFat,
            fiber: totalFiber,
            confidence: nil
        )
    }

    private var currentStreak: Int {
        let cal = Calendar.current
        let loggedDays = Set(foodLogs.map { cal.startOfDay(for: $0.day) })
        var start = cal.startOfDay(for: Date())
        if !loggedDays.contains(start) {
            start = cal.date(byAdding: .day, value: -1, to: start) ?? start
        }
        var streak = 0
        var current = start
        while loggedDays.contains(current) {
            streak += 1
            current = cal.date(byAdding: .day, value: -1, to: current) ?? current
        }
        return streak
    }

    private var foodLogsForSelectedDate: [FoodLogEntry] {
        let targetDay = Calendar.current.startOfDay(for: selectedDate)
        return foodLogs.filter { $0.day == targetDay }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func deleteFoodEntry(_ entry: FoodLogEntry) {
        withAnimation {
            modelContext.delete(entry)
            do {
                try modelContext.save()
            } catch {
                print("Error deleting food entry: \(error)")
            }
        }
    }

    private func changeDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = newDate
            }
        }
    }

    private func addAgain(_ entry: FoodLogEntry) {
        // Set the food description to the entry's name and trigger analysis
        viewModel.foodDescription = entry.foodName

        Task {
            await viewModel.logFood(on: selectedDate)
            // Clear input after successful log
            await MainActor.run {
                viewModel.foodDescription = ""
            }
        }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topNavigationBar
                textEditorView
                Spacer()
            }

            // Hide GoalExpandableView + NarratorButton when keyboard is visible
            if !isTextEditorFocused {
                VStack {
                    Spacer()
                    Spacer()

                    // Voice quality nudge banner (shown once if only default voice available)
                    if narrator.showVoiceNudge, aggregatedNutrition != nil {
                        HStack(spacing: 8) {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 12))
                                .foregroundColor(.orange)
                            Text("Download an enhanced voice in **Settings → Accessibility → Live Speech** for richer audio.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    // Narrator button — only visible when food is logged today
                    if let nutrition = aggregatedNutrition {
                        HStack {
                            Spacer()
                            NarratorButton(
                                isSpeaking: narrator.isSpeaking,
                                isGenerating: narrator.isGenerating
                            ) {
                                Task {
                                    await narrator.generateAndSpeak(
                                        nutrition: nutrition,
                                        goals: .default
                                    )
                                }
                            }
                            .padding(.trailing, 20)
                            .padding(.bottom, 8)
                        }
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                    }

                    GoalsExpandableView(
                        isExpanded: $isGoalsExpanded,
                        currentNutrition: aggregatedNutrition,
                        dailyGoals: .default
                    )
                    .onTapGesture {
                        if !isGoalsExpanded {
                            isGoalsExpanded = true
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Disambiguation overlay — Feature 3
            if let state = viewModel.disambiguationState {
                DisambiguationChipsView(
                    question: state.question,
                    options: state.options,
                    rawInput: state.rawInput,
                    onSelect: { option in
                        viewModel.disambiguationState = nil
                        Task {
                            await viewModel.logFood(on: selectedDate, coachOverride: option.label)
                            await MainActor.run {
                                if !viewModel.showError {
                                    HapticService.notify(.success)
                                    viewModel.foodDescription = ""
                                }
                            }
                        }
                    },
                    onAddAsTyped: {
                        viewModel.disambiguationState = nil
                        Task {
                            await viewModel.logFood(on: selectedDate, coachOverride: state.rawInput)
                            await MainActor.run {
                                if !viewModel.showError {
                                    HapticService.notify(.success)
                                    viewModel.foodDescription = ""
                                }
                            }
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    // Detect horizontal swipes
                    let horizontalAmount = abs(value.translation.width)
                    let verticalAmount = abs(value.translation.height)

                    // Must be primarily horizontal (1.8x more horizontal than vertical)
                    // and swipe at least 70 points
                    let isHorizontalSwipe = horizontalAmount > verticalAmount * 1.8 && horizontalAmount > 70

                    if isHorizontalSwipe && !isGoalsExpanded {
                        HapticService.selectionChanged()
                        if value.translation.width > 0 {
                            // Swipe right - go to previous day
                            changeDate(by: -1)
                        } else {
                            // Swipe left - go to next day
                            changeDate(by: 1)
                        }
                    }
                }
        )
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onChange(of: viewModel.showError) { _, isError in
            if isError { HapticService.notify(.error) }
        }
        .sheet(isPresented: $showDatePicker) {
            datePickerSheet
        }
        .sheet(isPresented: $showStreak) {
            StreakDetailView()
        }
        .fullScreenCover(isPresented: $showProgressInsights) {
            ProgressInsightsView()
        }
        .onChange(of: foodLogs.count) { oldValue, newValue in
            if aggregatedNutrition != nil && oldValue == 0 {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    isGoalsExpanded = true
                }
            }
        }
    }

    private var topNavigationBar: some View {
        ZStack{
            HStack{
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "fork.knife")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.orange)
                    )
                
                Spacer()
                
                HStack(spacing: 14){
                   
                    Button(action: {
                        HapticService.impact(.light)
                        showStreak = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.orange)
                            Text("\(currentStreak)")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                    Button(action: {
                        HapticService.impact(.light)
                        showProgressInsights = true
                    }) {
                        HStack(spacing:4){
                            Image(systemName: "chart.bar.xaxis")
                                .font(.system(size: 16))
                                .foregroundColor(.orange)
                        }
                    }
                }
                .padding(.horizontal,8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .appShadow(radius: 8, y: 2)
                )
            }
            
            Button(action: {
                HapticService.impact(.light)
                showDatePicker = true
            }) {
                HStack(spacing: 8) {
                    Text(dateText)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(.systemBackground))
                        .appShadow(radius: 8, y: 2)
                )
            }
            
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemGroupedBackground))
    }
    
    private var textEditorView: some View {
        ZStack(alignment: .topLeading) {
            Color(.systemBackground)

            VStack(spacing: 0) {
                // Use List for swipe-to-delete functionality
                List {
                    // Display logged food items with energy
                    ForEach(foodLogsForSelectedDate) { entry in
                        HStack {
                            Text(entry.foodName)
                                .font(.r(14, .regular))
                                .foregroundColor(.primary)

                            Spacer()

                            Text("\(entry.calories) kcal")
                                .font(.r(14, .regular))
                                .foregroundColor(.gray)
                        }
                        .listRowInsets(EdgeInsets(top: 1, leading: 24, bottom: 1, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteFoodEntry(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button {
                                HapticService.impact(.light)
                                addAgain(entry)
                            } label: {
                                Label("Add Again", systemImage: "plus.circle.fill")
                            }

                            Divider()

                            Button(role: .destructive) {
                                deleteFoodEntry(entry)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                    }

                    // Input field for new entry embedded in List
                    HStack(alignment: .top, spacing: 12) {
                        TextField("Add food...", text: $viewModel.foodDescription)
                            .font(.r(14, .regular))
                            .textFieldStyle(.plain)
                            .focused($isTextEditorFocused)
                            .disabled(viewModel.isLoading)
                            .tint(.orange)
                            .submitLabel(.return)
                            .onSubmit {
                                if !viewModel.foodDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    triggerAnalysis()
                                }
                            }

                        if !viewModel.foodDescription.isEmpty {
                            Button(action: {
                                triggerAnalysis()
                            }) {
                                Group {
                                    if viewModel.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "sparkles")
                                            .font(.system(size: 16, weight: .semibold))
                                            .symbolEffect(.breathe, isActive: viewModel.isLoading)
                                    }
                                }
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.orange, Color.orange.opacity(0.8)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                                .shadow(color: .orange.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.isLoading)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)

                    // Placeholder when no foods logged
                    if foodLogsForSelectedDate.isEmpty && viewModel.foodDescription.isEmpty {
                        Text("Start logging your meals...")
                            .font(.system(size: 16))
                            .foregroundColor(.gray.opacity(0.5))
                            .listRowInsets(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .listRowSpacing(0)
                .scrollContentBackground(.hidden)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            // Detect pull-down at top to dismiss keyboard
                            // Only trigger for vertical drags (not horizontal swipes)
                            let isVerticalDrag = abs(value.translation.height) > abs(value.translation.width)
                            if isVerticalDrag && value.translation.height > 100 && isTextEditorFocused {
                                isTextEditorFocused = false
                            }
                        }
                )
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isTextEditorFocused = true
            }
        }
    }
    
    private func triggerAnalysis() {
        isTextEditorFocused = false

        let foodInput = viewModel.foodDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !foodInput.isEmpty else { return }

        Task {
            await viewModel.logFood(on: selectedDate)
            // Clear input after successful log
            await MainActor.run {
                if !viewModel.showError {
                    HapticService.notify(.success)
                }
                viewModel.foodDescription = ""
            }
        }
    }
    
    private var datePickerSheet: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                
                Spacer()
            }
            .navigationTitle("Select Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Today") {
                        selectedDate = Date()
                    }
                    .foregroundColor(.orange)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        showDatePicker = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private var dateText: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        } else if calendar.isDateInYesterday(selectedDate) {
            return "Yesterday"
        } else if calendar.isDateInTomorrow(selectedDate) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: selectedDate)
        }
    }

    private var resultsSection: some View {
        VStack(spacing: 20) {
            if let info = viewModel.nutritionalInfo {
                VStack(spacing: 8) {
                    Text(info.foodName)
                        .font(.title2)
                        .fontWeight(.bold)

                    if let serving = info.servingSize {
                        Text(serving)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let confidence = info.confidence {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(Int(confidence * 100))% confidence")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemBackground))
                        .appShadow(radius: 10, y: 4)
                )

                nutritionGrid(info: info)
            }
        }
    }

    private func nutritionGrid(info: NutritionalInfo) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                nutritionCard(
                    icon: "flame.fill",
                    color: .orange,
                    label: "Calories",
                    value: "\(info.calories)",
                    unit: "kcal"
                )
                
                nutritionCard(
                    icon: "figure.strengthtraining.traditional",
                    color: .red,
                    label: "Protein",
                    value: String(format: "%.1f", info.protein),
                    unit: "g"
                )
            }
            
            HStack(spacing: 12) {
                nutritionCard(
                    icon: "leaf.fill",
                    color: .blue,
                    label: "Carbs",
                    value: String(format: "%.1f", info.carbs),
                    unit: "g"
                )
                
                nutritionCard(
                    icon: "drop.fill",
                    color: .yellow,
                    label: "Fat",
                    value: String(format: "%.1f", info.fat),
                    unit: "g"
                )
            }
            
            nutritionCardFullWidth(
                icon: "chevron.up.chevron.down",
                color: .green,
                label: "Fiber",
                value: String(format: "%.1f", info.fiber),
                unit: "g"
            )
        }
    }
    
    private func nutritionCard(icon: String, color: Color, label: String, value: String, unit: String) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.title3)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .appShadow(radius: 10, y: 4)
        )
    }
    
    private func nutritionCardFullWidth(icon: String, color: Color, label: String, value: String, unit: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .appShadow(radius: 10, y: 4)
        )
    }

    private var clearButton: some View {
        Button(action: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextEditorFocused = true
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 18, weight: .semibold))
                Text("Log Another Meal")
                    .font(.system(size: 17, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue, Color.blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .foregroundColor(.white)
            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
        }
    }
}

#Preview("Light") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodLogEntry.self, configurations: config)
    return HomeView(viewModel: HomeViewModel(modelContext: container.mainContext))
        .modelContainer(container)
}

#Preview("Dark") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: FoodLogEntry.self, configurations: config)
    return HomeView(viewModel: HomeViewModel(modelContext: container.mainContext))
        .modelContainer(container)
        .preferredColorScheme(.dark)
}
