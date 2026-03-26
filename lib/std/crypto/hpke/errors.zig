//! Public error set for HPKE.

/// Errors that can occur during HPKE operations.
pub const HpkeError = error{
    /// The KEM identifier is not supported.
    InvalidKem,
    /// The KDF identifier is not supported.
    InvalidKdf,
    /// The AEAD identifier is not supported.
    InvalidAead,
    /// Decapsulation of the shared secret failed.
    DecapsFailed,
    /// Encapsulation of the shared secret failed.
    EncapsFailed,
    /// Encryption failed (e.g., due to invalid parameters).
    EncryptionFailed,
    /// Decryption failed (e.g., authentication tag mismatch).
    DecryptionFailed,
    /// A key or ciphertext has the wrong length.
    InvalidKeyLength,
    /// The HPKE context is in an invalid state for the requested operation.
    InvalidContext,
    /// The sequence number would overflow.
    SequenceOverflow,
    /// The requested operation is not supported by this KEM.
    OperationNotSupported,
    /// The peer's public key is invalid or caused a DH operation to fail.
    InvalidPeerKey,
    /// Failed to derive a private key from a seed (e.g., after 255 attempts).
    DeriveKeyFailed,
    /// Memory allocation failed.
    AllocationFailed,
    /// Input string (ikm, info, etc.) exceeds the implementation limit.
    InputTooLong,
};
