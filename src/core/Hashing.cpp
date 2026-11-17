// Textpad++ — hashing via CommonCrypto. GPL-3.0-or-later.
#include "core/Hashing.h"

#include <CommonCrypto/CommonDigest.h>
#include <cstdio>
#include <vector>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"  // CC_MD5 / CC_SHA1 are required for compatibility

namespace tpp {

namespace {
std::string toHex(const unsigned char* d, size_t n) {
    static const char* hex = "0123456789abcdef";
    std::string s(n * 2, '0');
    for (size_t i = 0; i < n; ++i) { s[2 * i] = hex[d[i] >> 4]; s[2 * i + 1] = hex[d[i] & 0xF]; }
    return s;
}

struct Hasher {
    HashAlgorithm a;
    CC_MD5_CTX md5; CC_SHA1_CTX sha1; CC_SHA256_CTX sha256; CC_SHA512_CTX sha512;
    explicit Hasher(HashAlgorithm alg) : a(alg) {
        switch (a) {
            case HashAlgorithm::MD5: CC_MD5_Init(&md5); break;
            case HashAlgorithm::SHA1: CC_SHA1_Init(&sha1); break;
            case HashAlgorithm::SHA256: CC_SHA256_Init(&sha256); break;
            case HashAlgorithm::SHA512: CC_SHA512_Init(&sha512); break;
        }
    }
    void update(const void* p, size_t n) {
        while (n > 0) {
            CC_LONG chunk = n > 0x40000000 ? 0x40000000 : static_cast<CC_LONG>(n);
            switch (a) {
                case HashAlgorithm::MD5: CC_MD5_Update(&md5, p, chunk); break;
                case HashAlgorithm::SHA1: CC_SHA1_Update(&sha1, p, chunk); break;
                case HashAlgorithm::SHA256: CC_SHA256_Update(&sha256, p, chunk); break;
                case HashAlgorithm::SHA512: CC_SHA512_Update(&sha512, p, chunk); break;
            }
            p = static_cast<const char*>(p) + chunk;
            n -= chunk;
        }
    }
    std::string finish() {
        unsigned char d[CC_SHA512_DIGEST_LENGTH];
        switch (a) {
            case HashAlgorithm::MD5: CC_MD5_Final(d, &md5); return toHex(d, CC_MD5_DIGEST_LENGTH);
            case HashAlgorithm::SHA1: CC_SHA1_Final(d, &sha1); return toHex(d, CC_SHA1_DIGEST_LENGTH);
            case HashAlgorithm::SHA256: CC_SHA256_Final(d, &sha256); return toHex(d, CC_SHA256_DIGEST_LENGTH);
            case HashAlgorithm::SHA512: CC_SHA512_Final(d, &sha512); return toHex(d, CC_SHA512_DIGEST_LENGTH);
        }
        return {};
    }
};
} // namespace

const char* hashName(HashAlgorithm a) {
    switch (a) {
        case HashAlgorithm::MD5: return "MD5";
        case HashAlgorithm::SHA1: return "SHA-1";
        case HashAlgorithm::SHA256: return "SHA-256";
        case HashAlgorithm::SHA512: return "SHA-512";
    }
    return "";
}

std::string hashHex(HashAlgorithm a, const std::string& bytes) {
    Hasher h(a);
    h.update(bytes.data(), bytes.size());
    return h.finish();
}

bool hashFileHex(HashAlgorithm a, const std::string& path, std::string& outHex, std::string& error) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) { error = "Cannot open file"; return false; }
    Hasher h(a);
    std::vector<char> buf(1 << 20);
    size_t n;
    while ((n = std::fread(buf.data(), 1, buf.size(), f)) > 0) h.update(buf.data(), n);
    bool ok = !std::ferror(f);
    std::fclose(f);
    if (!ok) { error = "Read error"; return false; }
    outHex = h.finish();
    return true;
}

} // namespace tpp
