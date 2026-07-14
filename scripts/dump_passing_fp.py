#!/usr/bin/env python3
"""
Run each FP batch through the RTL, collect only passing vectors, write to
Efficient_MAC/bhav_sim/tv_fp_passing.txt for waveform capture.
"""
import sys
sys.path.insert(0, str(__import__('pathlib').Path(__file__).parent))

from parallel_verify import (
    BATCH_CONFIG, run_batch, verify, _write_tv,
    compile_rtl, REPO
)

OUT = REPO / "Efficient_MAC/bhav_sim/tv_fp_passing.txt"

compile_rtl()

passing = []
for (name, gen_fn, n_per_batch, n_batches) in BATCH_CONFIG:
    for i in range(n_batches):
        bname = f"{name}_{i}"
        vectors = gen_fn(n_per_batch, seed=42 + i)
        fp_vectors = [(fl, A, B, acc) for (fl, A, B, acc) in vectors if fl == 1]
        if not fp_vectors:
            continue

        batch_name, vecs, stdout, err = run_batch((bname, fp_vectors))
        if stdout is None:
            print(f"[{bname}] sim error: {err}")
            continue

        result = verify(bname, fp_vectors, stdout)
        print(f"[{bname}] pass={result['pass']} fail={result['fail']} skip={result['skip']}")

        # collect passing vectors by re-running verify logic inline
        from parallel_verify import exact_ref, parse_output
        records = parse_output(stdout)
        for idx, (fl, A, B, acc) in enumerate(fp_vectors):
            out_time = 15000 + idx * 10000 + 30000
            rec = records.get(out_time)
            if rec is None:
                continue
            expected = exact_ref(A, B, acc)
            if expected is None:
                continue
            if expected == rec["OUT_fp"]:
                passing.append((fl, A, B, acc))

print(f"\nTotal passing FP vectors: {len(passing)}")
_write_tv(passing, str(OUT))
print(f"Written to {OUT}")
