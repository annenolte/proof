import Foundation

// MARK: - Dependencies we do not own

/// Where the API key comes from.
///
/// Deliberately a one-method protocol rather than a direct dependency on the
/// keychain store: this stage must be buildable and testable without it, and
/// in production the key is a server-side secret behind a proxy anyway — it
/// must never ship in the app bundle (SPEC §5.7).
public protocol OpenAIKeyProviding: Sendable {
    /// Returns nil when no key is configured, which is a normal state, not an
    /// error: the app is fully useful with the cloud layer switched off.
    func openAIKey() throws -> String?
}

/// A key held in memory. Fine for previews and tests; never for the shipped app.
public struct StaticKeyProvider: OpenAIKeyProviding {
    public let key: String?
    public init(_ key: String?) { self.key = key }
    public func openAIKey() throws -> String? { key }
}

/// The seam that makes every failure path in this file testable without a
/// network: 429s, truncation, malformed bodies, and hangs.
public protocol HTTPTransporting: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransporting {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LLMError.transport("non-HTTP response")
        }
        return (data, http)
    }
}

// MARK: - Request

public struct LLMObjectRequest: Sendable, Equatable {
    public var objectID: UUID
    public var roomPlanCategory: String
    public var roomPlanAttributes: [String]
    public var extents: Extents
    public var floorContact: Bool
    public var roomKind: RoomKind?
    /// The crop. ~0.2 MP, 25–60 KB, EXIF-stripped, and the *only* pixels that
    /// ever leave the device: no full frames, no faces, no window views.
    public var jpeg: Data

    public init(
        objectID: UUID,
        roomPlanCategory: String,
        roomPlanAttributes: [String] = [],
        extents: Extents,
        floorContact: Bool,
        roomKind: RoomKind? = nil,
        jpeg: Data
    ) {
        self.objectID = objectID
        self.roomPlanCategory = roomPlanCategory
        self.roomPlanAttributes = roomPlanAttributes
        self.extents = extents
        self.floorContact = floorContact
        self.roomKind = roomKind
        self.jpeg = jpeg
    }

    /// The text line that accompanies the image.
    ///
    /// Load-bearing: telling the model the LiDAR numbers and instructing it to
    /// trust them over its visual size impression is what makes mass estimates
    /// tractable at all. Without it the model guesses the size from the photo
    /// and everything downstream inherits that error.
    public var promptLine: String {
        let e = extents
        let volume = e.volume
        var parts = [
            "id=\(objectID.uuidString)",
            "roomplan_category=\(roomPlanCategory)",
        ]
        if !roomPlanAttributes.isEmpty {
            parts.append("roomplan_attributes=\(roomPlanAttributes.joined(separator: ","))")
        }
        parts.append(String(
            format: "dimensions_m: width=%.2f depth=%.2f height=%.2f (volume=%.3f m^3)",
            e.width, e.depth, e.height, volume))
        parts.append("floor_contact=\(floorContact)")
        if let roomKind {
            parts.append("room=\(roomKind.rawValue)")
        }
        return parts.joined(separator: " | ")
    }
}

// MARK: - Client

public protocol ObjectLLMClienting: Sendable {
    func refine(_ request: LLMObjectRequest) async throws -> LLMObjectProperties
}

/// Stage 3: `gpt-5-mini` over `/v1/responses` with strict Structured Outputs.
///
/// Everything about the shape of this call was measured rather than assumed:
///
/// * **`/v1/responses`, not `/v1/chat/completions`** — it is the only endpoint
///   exposing `reasoning.effort`, which is the single biggest latency lever on
///   GPT-5-class models; `store: false` gives per-request retention opt-out;
///   and the schema is inline rather than double-wrapped.
/// * **`gpt-5-mini`** — on the same crop and schema, `gpt-4o` answered 40 kg
///   (35–45) at confidence **0.95**, which is both wrong and overconfident,
///   while `gpt-5-mini` answered 80 kg (60–120) at 0.70. Calibrated uncertainty
///   is what makes the merge work at all; an overconfident narrow range is
///   worse than no answer.
/// * **`detail: "low"`** — `low` and `high` produced materially identical
///   answers while `high` cost several times the input tokens. Our crops are
///   already tight; cropping is what `detail: high` is for and we did it.
/// * **Never batch.** Twelve objects in one request took 33.8 s; twelve
///   parallel requests took 6.7 s. Output tokens generate serially inside one
///   response, so batching serialises what could be concurrent — and it
///   degraded quality through cross-item anchoring.
public struct OpenAIClassifier: ObjectLLMClienting {

    public struct Configuration: Sendable {
        public var endpoint: URL
        /// Pinned to the dated snapshot so a silent model swap cannot move
        /// every mass estimate in the app overnight.
        public var model: String
        public var reasoningEffort: String
        public var maxOutputTokens: Int
        /// Per-request wall clock. Above this we fall through to the prior.
        public var timeout: TimeInterval
        /// 429 / 5xx only.
        public var maxRetries: Int
        public var baseBackoff: TimeInterval
        public var backoffFactor: Double
        /// A per-app-version constant improves cache routing.
        public var promptCacheKey: String

        public init(
            endpoint: URL = URL(string: "https://api.openai.com/v1/responses")!,
            model: String = "gpt-5-mini-2025-08-07",
            reasoningEffort: String = "low",
            maxOutputTokens: Int = 1200,
            timeout: TimeInterval = 12,
            maxRetries: Int = 2,
            baseBackoff: TimeInterval = 0.5,
            backoffFactor: Double = 2,
            promptCacheKey: String = "tremor-object-understanding-v1"
        ) {
            self.endpoint = endpoint
            self.model = model
            self.reasoningEffort = reasoningEffort
            self.maxOutputTokens = maxOutputTokens
            self.timeout = timeout
            self.maxRetries = maxRetries
            self.baseBackoff = baseBackoff
            self.backoffFactor = backoffFactor
            self.promptCacheKey = promptCacheKey
        }

        public static let `default` = Configuration()
    }

    public var configuration: Configuration
    private let keyProvider: any OpenAIKeyProviding
    private let transport: any HTTPTransporting
    /// Injectable so tests do not actually sleep through a backoff.
    private let sleeper: @Sendable (TimeInterval) async throws -> Void

    /// The default key provider is the app's secret store, so the shipped path
    /// reads the key the settings screen wrote and nothing has to remember to
    /// wire the two together. Tests pass a `StaticKeyProvider`.
    public init(
        keyProvider: any OpenAIKeyProviding = SecretStore.live,
        configuration: Configuration = .default,
        transport: any HTTPTransporting = URLSessionTransport(),
        sleeper: (@Sendable (TimeInterval) async throws -> Void)? = nil
    ) {
        self.keyProvider = keyProvider
        self.configuration = configuration
        self.transport = transport
        self.sleeper = sleeper ?? { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
        }
    }

    // MARK: - The system prompt
    //
    // Verbatim from SPEC §5.5.4, which is verbatim from the verified live run.
    //
    // The clause "lower `confidence` and widen the mass range rather than
    // guessing narrowly" is load-bearing and must not be edited without
    // re-running the calibration harness: it is the difference between
    // gpt-5-mini's honest 0.70 / 60–120 kg and gpt-4o's 0.95 / 35–45 kg, and
    // the merge depends on that honesty.
    //
    // The density table is inlined for two reasons: it genuinely improves
    // grounding, and it pushes the shared prefix past the 1024 tokens OpenAI's
    // automatic prompt caching requires. Measured at 1056 input tokens with the
    // table, versus 857 without — just over the line, which is the point.
    public static let systemPrompt = """
        You are a physical-properties estimator for a home earthquake/child safety app.
        For each object you are given: a cropped photo, the RoomPlan category the device
        assigned, and exact 3D dimensions in metres (width x depth x height) measured by
        LiDAR. The dimensions are ground truth - trust them over your visual size
        impression. Estimate mass from plausible material density and construction for the
        observed volume, including typical contents (books on shelves, clothes in a
        dresser). Prefer the specific real-world product archetype the photo most
        resembles. If the photo is ambiguous, lower `confidence` and widen the mass range
        rather than guessing narrowly. Answer only with the JSON object required by the
        schema.

        Reference effective bulk densities (kg per cubic metre of bounding-box volume,
        including typical contents):
          bookshelf open loaded 200 - bookshelf empty 70 - bookshelf glass doors 190 -
          dresser 160 - wardrobe 110 - nightstand 190 - sideboard/TV unit 150 -
          filing cabinet loaded 320 - kitchen base cabinet 140 - sofa 55 - armchair 70 -
          dining table 90 - coffee table 110 - dining chair 100 - bed 50 - desk 100 -
          refrigerator 190 - stove/oven 240 - dishwasher 220 - washer/dryer 300 -
          piano upright 430. Flat-panel TVs do not follow a volume model: use
          mass_kg ~= 11 * (screen width m * screen height m) + 2.
        """

    // MARK: - The strict schema

    /// Verified live against the API. Three traps are encoded here, each of
    /// which was a real failure during research:
    ///
    /// * `additionalProperties: false` **and** every property listed in
    ///   `required` are both mandatory. Omit one and the request 400s.
    /// * Never put a sentinel like `"none"` in an enum — an earlier schema did,
    ///   and the model emitted `["metal", "none"]`, a self-contradictory answer.
    ///   An empty array is the correct way to say "no secondary material".
    /// * `minimum`/`maximum` are accepted under `strict: true` and usefully
    ///   steer the model, but they are **not enforced by the decoder**, so
    ///   every number is still validated client-side.
    /// Every property, in schema order.
    public static let schemaPropertyNames = [
        "object_id", "object_type", "material_primary", "material_secondary",
        "mass_kg_estimate", "mass_kg_min", "mass_kg_max",
        "center_of_mass_height_fraction", "mounting", "fragility",
        "contains_glass", "contents_can_fall_out", "tip_over_risk",
        "confidence", "notes",
    ]

    public static let mountingWireValues = [
        "freestanding_floor", "wall_mounted", "on_top_of_furniture",
        "ceiling_suspended", "built_in_fixed", "countertop", "unknown",
    ]

    public static var responseSchema: [String: Any] {
        func string(_ description: String) -> [String: Any] {
            ["type": "string", "description": description]
        }
        func number(_ description: String) -> [String: Any] {
            ["type": "number", "description": description]
        }
        func enumerated(_ values: [String]) -> [String: Any] {
            ["type": "string", "enum": values]
        }
        func unitInterval(_ description: String) -> [String: Any] {
            ["type": "number", "minimum": 0.0, "maximum": 1.0, "description": description]
        }

        var properties: [String: Any] = [:]
        properties["object_id"] = string("Echo of the id given in the prompt.")
        properties["object_type"] = string(
            "Specific everyday name, e.g. 'tall open bookshelf', 'chest of drawers', 'flat-screen TV on stand'.")
        properties["material_primary"] = enumerated(MaterialClass.primaryWireValues)
        properties["material_secondary"] = [
            "type": "array",
            "description": "Other materials present; empty array if none.",
            "items": enumerated(MaterialClass.secondaryWireValues),
        ] as [String: Any]
        properties["mass_kg_estimate"] = number(
            "Best point estimate of total mass in kg INCLUDING typical contents.")
        properties["mass_kg_min"] = number("Low end of a plausible range in kg.")
        properties["mass_kg_max"] = number("High end of a plausible range in kg.")
        properties["center_of_mass_height_fraction"] = unitInterval(
            "Height of centre of mass as a fraction of object height, 0.0 (floor) to 1.0 (top). Typical: 0.5 uniform, 0.35 bottom-heavy dresser, 0.6+ top-heavy loaded shelf.")
        properties["mounting"] = enumerated(mountingWireValues)
        properties["fragility"] = enumerated(Fragility.allCases.map(\.rawValue))
        properties["contains_glass"] = ["type": "boolean"] as [String: Any]
        properties["contents_can_fall_out"] = [
            "type": "boolean",
            "description": "True if open shelves / unlatched drawers / loose items on top can spill during shaking.",
        ] as [String: Any]
        properties["tip_over_risk"] = enumerated(["low", "medium", "high"])
        properties["confidence"] = unitInterval(
            "0.0-1.0 confidence in the overall classification.")
        properties["notes"] = string("<=140 chars, what drove the estimate.")

        return [
            "type": "object",
            "additionalProperties": false,
            "required": schemaPropertyNames,
            "properties": properties,
        ]
    }

    /// The request body, exposed so tests can assert its exact shape without a
    /// network round trip.
    public static func requestBody(
        for request: LLMObjectRequest, configuration: Configuration,
        maxOutputTokens: Int? = nil
    ) throws -> Data {
        let base64 = request.jpeg.base64EncodedString()
        let body: [String: Any] = [
            "model": configuration.model,
            "input": [
                [
                    "role": "system",
                    "content": [["type": "input_text", "text": systemPrompt]],
                ],
                [
                    "role": "user",
                    "content": [
                        ["type": "input_text", "text": request.promptLine],
                        [
                            "type": "input_image",
                            "image_url": "data:image/jpeg;base64,\(base64)",
                            "detail": "low",
                        ],
                    ],
                ],
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "tremor_object_properties",
                    "strict": true,
                    "schema": responseSchema,
                ],
            ],
            "reasoning": ["effort": configuration.reasoningEffort],
            "max_output_tokens": maxOutputTokens ?? configuration.maxOutputTokens,
            // Explicit per-request opt-out of server-side retention. Verified
            // accepted and reflected back in the response.
            "store": false,
            "prompt_cache_key": configuration.promptCacheKey,
        ]
        // `temperature` is deliberately absent: GPT-5 reasoning models do not
        // accept it and report 1.0 regardless.
        return try JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Decoding

    private struct Envelope: Decodable {
        struct Output: Decodable {
            struct Content: Decodable {
                let type: String
                let text: String?
            }
            let type: String
            let content: [Content]?
        }
        struct IncompleteDetails: Decodable { let reason: String? }
        let status: String?
        let incomplete_details: IncompleteDetails?
        let output: [Output]?
    }

    /// Pulls the strict-JSON payload out of a `/v1/responses` envelope.
    ///
    /// `output[0]` is a **`reasoning` item, not the message** — indexing it is
    /// the single most common way to get this wrong. Always search by type.
    ///
    /// Truncation is real and was reproduced: with a small `max_output_tokens`
    /// the API returns `status: "incomplete"` and `output` containing *only* a
    /// reasoning item — no message, not even partial JSON.
    public static func decode(responseBody data: Data) throws -> LLMObjectProperties {
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw LLMError.decoding("envelope: \(error)")
        }
        if let status = envelope.status, status != "completed" {
            throw LLMError.incomplete(reason: envelope.incomplete_details?.reason ?? status)
        }
        guard let text = envelope.output?
            .first(where: { $0.type == "message" })?
            .content?
            .first(where: { $0.type == "output_text" })?
            .text
        else {
            throw LLMError.noMessage
        }
        do {
            return try JSONDecoder().decode(LLMObjectProperties.self, from: Data(text.utf8))
        } catch {
            throw LLMError.decoding("payload: \(error)")
        }
    }

    // MARK: - The call

    public func refine(_ request: LLMObjectRequest) async throws -> LLMObjectProperties {
        guard let key = try keyProvider.openAIKey(), !key.isEmpty else {
            throw LLMError.noAPIKey
        }

        var attempt = 0
        var budget = configuration.maxOutputTokens
        var retriedTruncation = false
        var retriedDecode = false

        while true {
            try Task.checkCancellation()

            let body = try OpenAIClassifier.requestBody(
                for: request, configuration: configuration, maxOutputTokens: budget)
            var urlRequest = URLRequest(url: configuration.endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
            urlRequest.timeoutInterval = configuration.timeout
            let attemptRequest = urlRequest

            do {
                let (data, response) = try await withTimeout(configuration.timeout) {
                    try await self.transport.send(attemptRequest)
                }

                switch response.statusCode {
                case 200..<300:
                    return try OpenAIClassifier.decode(responseBody: data)

                case 429:
                    let retryAfter = response.value(forHTTPHeaderField: "Retry-After")
                        .flatMap(TimeInterval.init)
                    guard attempt < configuration.maxRetries else {
                        throw LLMError.rateLimited(retryAfter: retryAfter)
                    }
                    try await backOff(attempt: attempt, retryAfter: retryAfter)
                    attempt += 1

                case 401:
                    throw LLMError.unauthorized
                case 400, 403:
                    // Never retried. The caller disables the cloud layer for
                    // the whole session and shows one non-modal toast.
                    throw LLMError.permanent(status: response.statusCode)

                case 500...599:
                    guard attempt < configuration.maxRetries else {
                        throw LLMError.server(status: response.statusCode)
                    }
                    try await backOff(attempt: attempt, retryAfter: nil)
                    attempt += 1

                default:
                    throw LLMError.server(status: response.statusCode)
                }
            } catch let error as LLMError {
                switch error {
                case .incomplete where !retriedTruncation:
                    // Retry exactly once with a doubled budget.
                    retriedTruncation = true
                    budget *= 2
                case .decoding where !retriedDecode, .noMessage where !retriedDecode:
                    // Shouldn't happen under `strict: true`, but middleboxes
                    // and truncation exist, and a "completed" response with no
                    // message at all is the same class of malformed answer.
                    // One retry, then the prior.
                    retriedDecode = true
                    try await backOff(attempt: 0, retryAfter: nil)
                default:
                    throw error
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch let error as URLError where error.code == .timedOut {
                throw LLMError.timedOut
            } catch {
                throw LLMError.transport(String(describing: error))
            }
        }
    }

    /// Exponential backoff with full jitter, honouring `Retry-After`. Total
    /// added latency is bounded at roughly 3 s across the two permitted
    /// retries, which keeps the room-level budget intact.
    private func backOff(attempt: Int, retryAfter: TimeInterval?) async throws {
        if let retryAfter {
            try await sleeper(min(retryAfter, 5))
            return
        }
        let ceiling = configuration.baseBackoff * pow(configuration.backoffFactor, Double(attempt))
        try await sleeper(Double.random(in: 0...ceiling))
    }

    /// A wall-clock bound that holds regardless of transport. `URLRequest`'s
    /// own `timeoutInterval` covers the real network; this covers everything,
    /// including a stub that never returns, and it propagates cancellation.
    ///
    /// Deliberately uses real time rather than the injectable `sleeper`: a test
    /// that shortens the backoff must not thereby make every request time out.
    private func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                throw LLMError.timedOut
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw LLMError.timedOut }
            return first
        }
    }
}
