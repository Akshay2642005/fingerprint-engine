/// The set of deterministic computations the engine can perform.
///
/// Tags are explicit u8 values so requests survive serialization and
/// versioning: an unknown tag is caught at the dispatch boundary
/// (`invalid_request`) instead of being coerced to a valid operation.
/// Non-exhaustive so wire tags from newer peers degrade gracefully.
pub const Operation = enum(u8) {
    validate = 1, // validation + normalization passes → warnings
    normalize = 2, // canonical normalization → normalized package
    serialize = 3, // model → bytes (codec from request)
    deserialize = 4, // bytes → model
    hash = 5, // canonical digest (workers only; not exported to wasm)
    entropy = 6, // entropy score
    similarity = 7, // two packages (a, b) → score
    risk = 8, // risk assessment
    package = 9, // validate + normalize + serialize (browser's call)
    _,
};
