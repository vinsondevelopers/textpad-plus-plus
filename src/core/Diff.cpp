// Textpad++ — differences. GPL-3.0-or-later.
#include "core/Diff.h"
#include <algorithm>
#include <functional>

namespace tpp::diff {
namespace {

struct Myers {
    const uint64_t* a;
    const uint64_t* b;
    std::vector<long> vf, vb;
    std::vector<Hunk>* out;

    // the middle snake of a[a0, a1) x b[b0, b1)
    void middle(long a0, long a1, long b0, long b1, long& x0, long& y0, long& x1, long& y1) {
        const long n = a1 - a0, m = b1 - b0, delta = n - m, max = (n + m + 1) / 2 + 1, off = max;
        vf.assign(2 * max + 2, 0);
        vb.assign(2 * max + 2, 0);
        vf[off + 1] = 0;
        vb[off + 1] = 0;
        const bool odd = delta & 1;
        for (long d = 0; d <= max; ++d) {
            for (long k = -d; k <= d; k += 2) {
                long x = (k == -d || (k != d && vf[off + k - 1] < vf[off + k + 1])) ? vf[off + k + 1] : vf[off + k - 1] + 1;
                long y = x - k;
                const long sx = x, sy = y;
                while (x < n && y < m && a[a0 + x] == b[b0 + y]) { ++x; ++y; }
                vf[off + k] = x;
                if (odd && k - delta >= -(d - 1) && k - delta <= d - 1 && x + vb[off + delta - k] >= n) {
                    x0 = a0 + sx; y0 = b0 + sy; x1 = a0 + x; y1 = b0 + y; return;
                }
            }
            for (long k = -d; k <= d; k += 2) {
                long x = (k == -d || (k != d && vb[off + k - 1] < vb[off + k + 1])) ? vb[off + k + 1] : vb[off + k - 1] + 1;
                long y = x - k;
                const long sx = x, sy = y;
                while (x < n && y < m && a[a1 - 1 - x] == b[b1 - 1 - y]) { ++x; ++y; }
                vb[off + k] = x;
                if (!odd && delta - k >= -d && delta - k <= d && x + vf[off + delta - k] >= n) {
                    x0 = a1 - x; y0 = b1 - y; x1 = a1 - sx; y1 = b1 - sy; return;
                }
            }
        }
        x0 = a0; y0 = b0; x1 = a0; y1 = b0;   // not reached
    }

    void add(long a0, long a1, long b0, long b1) {
        if (a0 == a1 && b0 == b1) return;
        if (!out->empty()) {
            Hunk& h = out->back();
            if (h.aStart + h.aCount == (size_t)a0 && h.bStart + h.bCount == (size_t)b0) { h.aCount += a1 - a0; h.bCount += b1 - b0; return; }
        }
        out->push_back({(size_t)a0, (size_t)(a1 - a0), (size_t)b0, (size_t)(b1 - b0)});
    }

    void run(long a0, long a1, long b0, long b1) {
        while (a0 < a1 && b0 < b1 && a[a0] == b[b0]) { ++a0; ++b0; }
        while (a0 < a1 && b0 < b1 && a[a1 - 1] == b[b1 - 1]) { --a1; --b1; }
        if (a0 == a1 || b0 == b1) { add(a0, a1, b0, b1); return; }
        long x0, y0, x1, y1;
        middle(a0, a1, b0, b1, x0, y0, x1, y1);
        if ((x0 == a0 && y0 == b0 && x1 == a1 && y1 == b1) || (x1 - x0 == 0 && y1 - y0 == 0 && x0 == a0 && y0 == b0)) {
            add(a0, a1, b0, b1);   // no progress: report the whole block
            return;
        }
        run(a0, x0, b0, y0);
        run(x1, a1, y1, b1);
    }
};

uint64_t hashOf(const std::string& s, bool ignoreWs) {
    uint64_t h = 1469598103934665603ULL;
    for (unsigned char c : s) {
        if (ignoreWs && (c == ' ' || c == '\t')) continue;
        h = (h ^ c) * 1099511628211ULL;
    }
    return h;
}

} // namespace

std::vector<Hunk> diffSequences(const std::vector<uint64_t>& a, const std::vector<uint64_t>& b) {
    std::vector<Hunk> out;
    Myers m{a.data(), b.data(), {}, {}, &out};
    m.run(0, (long)a.size(), 0, (long)b.size());
    return out;
}

std::vector<std::string> splitLines(const std::string& t) {
    std::vector<std::string> lines;
    size_t s = 0;
    for (size_t i = 0; i < t.size(); ++i) {
        if (t[i] == '\n' || t[i] == '\r') {
            lines.push_back(t.substr(s, i - s));
            if (t[i] == '\r' && i + 1 < t.size() && t[i + 1] == '\n') ++i;
            s = i + 1;
        }
    }
    lines.push_back(t.substr(s));
    return lines;
}

std::vector<Hunk> diffLines(const std::string& a, const std::string& b, bool ignoreWs) {
    std::vector<uint64_t> ha, hb;
    for (auto& l : splitLines(a)) ha.push_back(hashOf(l, ignoreWs));
    for (auto& l : splitLines(b)) hb.push_back(hashOf(l, ignoreWs));
    return diffSequences(ha, hb);
}

std::vector<Hunk> diffChars(const std::string& a, const std::string& b) {
    // one element per UTF-8 character; hunks are converted back to byte offsets
    auto chars = [](const std::string& s, std::vector<uint64_t>& v, std::vector<size_t>& at) {
        for (size_t i = 0; i < s.size();) {
            size_t n = 1;
            const unsigned char c = (unsigned char)s[i];
            if (c >= 0xF0) n = 4; else if (c >= 0xE0) n = 3; else if (c >= 0xC0) n = 2;
            n = std::min(n, s.size() - i);
            uint64_t h = 0;
            for (size_t k = 0; k < n; ++k) h = h << 8 | (unsigned char)s[i + k];
            v.push_back(h);
            at.push_back(i);
            i += n;
        }
        at.push_back(s.size());
    };
    std::vector<uint64_t> va, vb;
    std::vector<size_t> pa, pb;
    chars(a, va, pa);
    chars(b, vb, pb);
    std::vector<Hunk> out;
    for (const Hunk& h : diffSequences(va, vb))
        out.push_back({pa[h.aStart], pa[h.aStart + h.aCount] - pa[h.aStart], pb[h.bStart], pb[h.bStart + h.bCount] - pb[h.bStart]});
    return out;
}

} // namespace tpp::diff
