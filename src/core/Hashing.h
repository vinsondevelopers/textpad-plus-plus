// Textpad++ — hashing (Tools > MD5 / SHA-1 / SHA-256 / SHA-512). GPL-3.0-or-later.
// Uses Apple CommonCrypto; no hand-written digest algorithms.
#pragma once

#include <string>

namespace tpp {

enum class HashAlgorithm { MD5, SHA1, SHA256, SHA512 };

const char* hashName(HashAlgorithm a);
std::string hashHex(HashAlgorithm a, const std::string& bytes);           // lowercase hex, as upstream
bool hashFileHex(HashAlgorithm a, const std::string& path, std::string& outHex, std::string& error);

} // namespace tpp
