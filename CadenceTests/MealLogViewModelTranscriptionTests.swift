import XCTest
@testable import WellPlate

// MARK: - Mock

@MainActor
private final class MockSpeechTranscriptionService: SpeechTranscriptionServiceProtocol {

    // MARK: Configuration

    var mockHasPermission: Bool = true
    var shouldThrowOnPermissions: Bool = false
    var shouldThrowOnStart: Bool = false
    var startError: SpeechTranscriptionError = .recognitionUnavailable

    // MARK: Call tracking

    private(set) var requestPermissionsCalled = false
    private(set) var startCalled = false
    private(set) var stopCalled = false
    private(set) var cancelCalled = false

    // MARK: Captured callbacks

    private(set) var capturedOnPartial: (@MainActor (String) -> Void)?
    private(set) var capturedOnFinal: (@MainActor (String) -> Void)?
    private(set) var capturedOnError: (@MainActor (SpeechTranscriptionError) -> Void)?

    // MARK: SpeechTranscriptionServiceProtocol

    var hasPermission: Bool { mockHasPermission }

    func requestPermissions() async throws {
        requestPermissionsCalled = true
        if shouldThrowOnPermissions {
            throw SpeechTranscriptionError.permissionDenied
        }
    }

    func startTranscription(
        onPartial: @escaping @MainActor (String) -> Void,
        onFinal: @escaping @MainActor (String) -> Void,
        onError: @escaping @MainActor (SpeechTranscriptionError) -> Void
    ) throws {
        startCalled = true
        if shouldThrowOnStart {
            throw startError
        }
        capturedOnPartial = onPartial
        capturedOnFinal = onFinal
        capturedOnError = onError
    }

    func stopTranscription() { stopCalled = true }
    func cancelTranscription() { cancelCalled = true }

    // MARK: Test helpers

    func fireOnPartial(_ text: String) { capturedOnPartial?(text) }
    func fireOnFinal(_ text: String) { capturedOnFinal?(text) }
    func fireOnError(_ error: SpeechTranscriptionError) { capturedOnError?(error) }
}

// MARK: - Tests

@MainActor
final class MealLogViewModelTranscriptionTests: XCTestCase {

    private var mock: MockSpeechTranscriptionService!
    private var viewModel: MealLogViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mock = MockSpeechTranscriptionService()
        viewModel = MealLogViewModel(homeViewModel: nil, speechService: mock)
    }

    override func tearDown() async throws {
        mock = nil
        viewModel = nil
        try await super.tearDown()
    }

    // MARK: - Start / stop toggle

    func test_startMealTranscription_setsIsTranscribing() async throws {
        viewModel.startMealTranscription()
        await Task.yield()
        XCTAssertTrue(viewModel.isTranscribing)
    }

    func test_startWhileTranscribing_callsStop() async throws {
        viewModel.startMealTranscription()
        await Task.yield()
        XCTAssertTrue(viewModel.isTranscribing)

        viewModel.startMealTranscription() // second tap — should toggle off
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertTrue(mock.stopCalled)
    }

    func test_stopMealTranscription_resetsStateImmediately() async throws {
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnPartial("rice and")
        XCTAssertEqual(viewModel.liveTranscript, "rice and")

        viewModel.stopMealTranscription()
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.liveTranscript, "")
        XCTAssertTrue(mock.stopCalled)
    }

    // MARK: - Transcript apply

    func test_onFinal_replacesEmptyFoodDescription() async throws {
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnFinal("oatmeal with berries")

        XCTAssertEqual(viewModel.foodDescription, "oatmeal with berries")
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.liveTranscript, "")
    }

    func test_onFinal_appendsToExistingText() async throws {
        viewModel.foodDescription = "rice"
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnFinal("and dal")

        XCTAssertEqual(viewModel.foodDescription, "rice and dal")
    }

    func test_onFinal_trimsExistingWhitespace() async throws {
        viewModel.foodDescription = "  rice  "
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnFinal("and dal")

        XCTAssertEqual(viewModel.foodDescription, "rice and dal")
    }

    func test_onFinal_emptyTranscript_doesNotChangeFoodDescription() async throws {
        viewModel.foodDescription = "existing text"
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnFinal("   ") // whitespace only

        XCTAssertEqual(viewModel.foodDescription, "existing text")
    }

    func test_onPartial_updatesLiveTranscript_withoutChangingFoodDescription() async throws {
        viewModel.foodDescription = "existing"
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnPartial("two eggs")

        XCTAssertEqual(viewModel.liveTranscript, "two eggs")
        XCTAssertEqual(viewModel.foodDescription, "existing") // unchanged until onFinal
        XCTAssertTrue(viewModel.isTranscribing) // still recording
    }

    // MARK: - Permission denial

    func test_permissionDenied_showsPermissionAlert() async throws {
        mock.mockHasPermission = false
        mock.shouldThrowOnPermissions = true

        viewModel.startMealTranscription()
        await Task.yield()
        await Task.yield() // extra yield for the async requestPermissions call

        XCTAssertTrue(viewModel.showTranscriptionPermissionAlert)
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertFalse(mock.startCalled)
    }

    func test_runtimePermissionDenied_fromStartThrow_showsPermissionAlert() async throws {
        mock.shouldThrowOnStart = true
        mock.startError = .permissionDenied

        viewModel.startMealTranscription()
        await Task.yield()

        XCTAssertTrue(viewModel.showTranscriptionPermissionAlert)
        XCTAssertFalse(viewModel.isTranscribing)
    }

    func test_recognitionUnavailable_showsGenericError() async throws {
        mock.shouldThrowOnStart = true
        mock.startError = .recognitionUnavailable

        viewModel.startMealTranscription()
        await Task.yield()

        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.showTranscriptionPermissionAlert)
        XCTAssertFalse(viewModel.isTranscribing)
    }

    // MARK: - Error callbacks

    func test_noSpeechDetected_doesNotClobberExistingText() async throws {
        viewModel.foodDescription = "avocado toast"
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnError(.noSpeechDetected)

        XCTAssertEqual(viewModel.foodDescription, "avocado toast")
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertFalse(viewModel.showError) // soft failure — no alert shown
    }

    func test_engineError_showsErrorAlert() async throws {
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnError(.engineError("Audio session interrupted."))

        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertEqual(viewModel.liveTranscript, "")
    }

    func test_onError_permissionDenied_showsPermissionAlert_notGenericError() async throws {
        viewModel.startMealTranscription()
        await Task.yield()
        mock.fireOnError(.permissionDenied)

        XCTAssertTrue(viewModel.showTranscriptionPermissionAlert)
        XCTAssertFalse(viewModel.showError)
    }

    // MARK: - applyTranscriptToFoodDescription (unit)

    func test_apply_replacesEmpty() {
        viewModel.foodDescription = ""
        viewModel.applyTranscriptToFoodDescription("banana smoothie")
        XCTAssertEqual(viewModel.foodDescription, "banana smoothie")
    }

    func test_apply_appendsWithSpace() {
        viewModel.foodDescription = "banana"
        viewModel.applyTranscriptToFoodDescription("smoothie")
        XCTAssertEqual(viewModel.foodDescription, "banana smoothie")
    }

    func test_apply_trimsTranscript() {
        viewModel.foodDescription = ""
        viewModel.applyTranscriptToFoodDescription("  banana  ")
        XCTAssertEqual(viewModel.foodDescription, "banana")
    }

    func test_apply_ignoresWhitespaceOnlyTranscript() {
        viewModel.foodDescription = "banana"
        viewModel.applyTranscriptToFoodDescription("   ")
        XCTAssertEqual(viewModel.foodDescription, "banana")
    }

    // MARK: - isLoading guard

    func test_startMealTranscription_doesNothingWhileLoading() async throws {
        // Simulate loading state — normally set by saveMeal, so we set directly
        viewModel.isLoading = true
        viewModel.startMealTranscription()
        await Task.yield()

        XCTAssertFalse(viewModel.isTranscribing)
        XCTAssertFalse(mock.startCalled)
    }
}
