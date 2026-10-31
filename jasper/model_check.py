"""Cycle-accurate Python model of async_fifo.sv with independent random clocks.
Checks the same invariants as jasper/async_fifo_props.sv; supports bug mutants."""
import random, sys

def b2g(b): return (b >> 1) ^ b
def g2b(g):
    b = 0
    while g:
        b ^= g
        g >>= 1
    return b

class Fifo:
    def __init__(s, D=8, W=3, mut=None):
        s.D, s.W, s.PW, s.mut = D, W, D.bit_length() - 1, mut
        s.M = 2 * D
        s.reset()
    def reset(s):
        s.wr_bin = s.rd_bin = s.wr_gray = s.rd_gray = 0
        s.rd_s1 = s.rd_s2 = s.wr_s1 = s.wr_s2 = 0
        s.full, s.empty, s.rd_data = 0, 1, 0
        s.mem = [None] * s.D
        s.mdl_wr = s.mdl_rd = 0
    def step(s, wt, rt, wr_data):
        D, M, PW, m = s.D, s.M, s.PW, s.mut
        n = {}
        if wt:
            wn = s.wr_bin if s.full else (s.wr_bin + 1) % M
            gn = wn if m == "gray_bug" else b2g(wn)
            if (not s.full) or m == "write_when_full":
                n["mem"] = (s.wr_bin % D, wr_data)
            tgt = s.rd_s2 ^ (0b11 << (PW - 1))          # {~top2, rest}
            if m == "full_noinv": tgt = s.rd_s2 ^ (0b10 << (PW - 1))
            if m == "full_early": tgt = b2g((g2b(s.rd_s2) + D - 1) % M)
            n["full"] = int(gn == tgt)
            n["wr_bin"], n["wr_gray"] = wn, gn
            n["rd_s1"], n["rd_s2"] = s.rd_gray, s.rd_s1
            if not s.full: n["mdl_wr"] = (s.mdl_wr + 1) % M
        if rt:
            rn = s.rd_bin if s.empty else (s.rd_bin + 1) % M
            gn = b2g(rn)
            n["empty"] = int((b2g(s.rd_bin) if m == "empty_late" else gn) == s.wr_s2)
            if not s.empty:
                idx = (rn if m == "rd_offbyone" else s.rd_bin) % D
                n["rd_data"] = s.mem[idx]
                n["mdl_rd"] = (s.mdl_rd + 1) % M
            n["rd_bin"], n["rd_gray"] = rn, gn
            n["wr_s1"], n["wr_s2"] = s.wr_gray, s.wr_s1
        if "mem" in n:
            i, v = n.pop("mem"); s.mem[i] = v
        for k, v in n.items(): setattr(s, k, v)

def check(s, prev=None, wt=False, rt=False):
    D, M = s.D, s.M
    occm = (s.mdl_wr - s.mdl_rd) % M
    occ = (s.wr_bin - s.rd_bin) % M
    wlag = (s.wr_bin - g2b(s.wr_s2)) % M
    rview = (g2b(s.wr_s2) - s.rd_bin) % M
    rlag = (s.rd_bin - g2b(s.rd_s2)) % M
    f = []
    if not occm <= D: f.append("no_overflow_underflow")
    if occm == D and not s.full: f.append("full_sound")
    if occm == 0 and not s.empty: f.append("empty_sound")
    if s.wr_bin != s.mdl_wr: f.append("wptr_matches_model")
    if s.rd_bin != s.mdl_rd: f.append("rptr_matches_model")
    if s.wr_gray != b2g(s.wr_bin): f.append("wgray_encoding")
    if s.rd_gray != b2g(s.rd_bin): f.append("rgray_encoding")
    if wlag + rview != occ: f.append("sync_view_split")
    if occ + rlag > D: f.append("stale_occ_bound")
    if prev:
        if wt and bin(s.wr_gray ^ prev[0]).count("1") > 1: f.append("wgray_onebit")
        if rt and bin(s.rd_gray ^ prev[1]).count("1") > 1: f.append("rgray_onebit")
    return f

def run(mut=None, steps=60000, seed=1, pw=0.5, pr=0.5, D=8, W=3):
    rnd = random.Random(seed)
    s = Fifo(D, W, mut)
    sym_idx, sym_data = rnd.randrange(2 * D), rnd.randrange(1 << W)
    fails, covers = {}, {"full": 0, "occ_full": 0, "full_and_empty": 0, "wrap": 0,
                         "tracked_read_ok": 0, "drain_after_full": 0}
    pend = False; was_full = False
    for _ in range(steps):
        wt, rt = rnd.random() < pw, rnd.random() < pr
        if not (wt or rt): continue
        for name in check(s): fails[name] = fails.get(name, 0) + 1
        occm = (s.mdl_wr - s.mdl_rd) % s.M
        covers["full"] += s.full; covers["occ_full"] += occm == D
        covers["full_and_empty"] += bool(s.full and s.empty)
        if occm == D: was_full = True
        if was_full and occm == 0: covers["drain_after_full"] += 1; was_full = False
        # environment assumption: tracked write carries sym_data
        wd = sym_data if (not s.full and s.mdl_wr == sym_idx) else rnd.randrange(1 << W)
        track = rt and not s.empty and s.mdl_rd == sym_idx
        prev = (s.wr_gray, s.rd_gray)
        wr_before = s.wr_bin
        s.step(wt, rt, wd)
        if wt and wr_before == 2 * D - 1 and s.wr_bin == 0: covers["wrap"] += 1
        for name in check(s, prev, wt, rt): fails[name] = fails.get(name, 0) + 1
        if track:
            if s.rd_data != sym_data: fails["data_integrity"] = fails.get("data_integrity", 0) + 1
            else: covers["tracked_read_ok"] += 1
    return fails, covers

if __name__ == "__main__":
    muts = [None, "write_when_full", "rd_offbyone", "empty_late", "gray_bug", "full_noinv", "full_early"]
    ratios = [(0.5, 0.5), (0.9, 0.1), (0.1, 0.9), (0.03, 0.97), (0.97, 0.03), (1.0, 1.0)]
    for m in muts:
        agg_f, agg_c = {}, {}
        for r_i, (pw, pr) in enumerate(ratios):
            for seed in range(6):
                f, c = run(m, 40000, seed * 100 + r_i, pw, pr)
                for k, v in f.items(): agg_f[k] = agg_f.get(k, 0) + v
                for k, v in c.items(): agg_c[k] = agg_c.get(k, 0) + v
        print(f"== mutant: {m}")
        print("   assertion failures:", agg_f if agg_f else "none")
        print("   covers hit:", {k: v for k, v in agg_c.items()})
