# FLEX-LSTM : Float-Fix Approximate Arithmetic LSTM

A mixed-precision LSTM inference accelerator combining **Q6.11 fixed-point** state representation with **FP8-E3M4 logarithmic floating-point** weight multiplication. The architecture achieves significant area and power reductions over standard FP32 implementations while maintaining competitive accuracy on NLP benchmarks.

---

## Overview

Standard LSTM hardware implementations rely on full-precision floating-point multipliers that are costly in area and power. This project replaces pre-activation multipliers with lightweight **Logarithmic Floating-Point (LFP) MAC units**, exploiting the identity:

```
log(a × b) = log(a) + log(b)
```

This transforms expensive mantissa multiplications into cheap additions in the exponent domain. Approximation is **strictly confined to the pre-activation stage** — recurrent state updates (cell state `C(t)` and hidden state `h(t)`) remain in exact Q6.11 fixed-point arithmetic to prevent exponential error propagation across timesteps.

---

## Key Features

- **Hybrid precision datapath**: E3M4 weights × Q6.11 activations
- **LFP MAC units**: replaces multipliers with log/antilog converters + adders
- **LUT-based Sigmoid & Tanh**: 384- and 176-entry tables, no polynomial approximation
- **Bit-exact Python–RTL co-simulation**: verified across >1 million weight/input combinations
- **Linear error accumulation**: approximation isolated to pre-activation; recurrence is exact
- **Post-synthesis verified**: GPDK 45 nm CMOS, nominal voltage and temperature

---

## Architecture

```
          xt  ht-1  ct-1
           │    │     │
    ┌──────▼────▼─────┤
    │   LFP MAC (ft)  │  ──► σ ──┐
    │   LFP MAC (it)  │  ──► σ ──┤──► ct = ft⊙ct-1 + it⊙gt
    │   LFP MAC (gt)  │  ──► tanh┤    ht = ot⊙tanh(ct)
    │   LFP MAC (ot)  │  ──► σ ──┘
    └─────────────────┘
       (Processing Domain)        (Recurrence Domain — exact Q6.11)
```

Each LFP MAC pipeline:
1. **Q6.11 → E3M4** converter (priority encoder + bit-shift)
2. **LFP-E3M4 multiplier** (log-domain addition via lightweight SOP approximation)
3. **E4M4 → Q6.11** converter (barrel shifter + saturation)
4. **Q6.11 accumulator**

---

## Number Formats

| Format | Bits | Usage | Max Quantization Error |
|--------|------|-------|----------------------|
| Q6.11 | 18 | Activations, hidden state, cell state | `\|eq\| ≤ 2⁻¹²` |
| E3M4 | 8 | Weights (pre-activation only) | `\|er\| ≤ 2⁻⁴` |

**Why this split?** Weights are read-only during inference and only appear in the pre-activation stage — so E3M4 conversion units are not duplicated per recurrence step. States require tighter, bounded error behavior across timesteps, which fixed-point provides deterministically.

---

## Hardware Results

Post-synthesis comparison (MAC unit, GPDK 45 nm):

| Implementation | Area (µm²) | Power (mW) | Delay (ns) |
|---------------|-----------|-----------|-----------|
| FP32 (40 nm) | 26,661 | 2.920 | 2.5 |
| FloatSD8 (40 nm) | 3,479 | 0.508 | 2.5 |
| **Float-Fix (45 nm)** | **771** | **0.021** | **1.8** |

**vs FP32 baseline:**
- Area reduction: ~34.5×
- Power reduction: ~139×
- Area–Delay Product (ADP): ~24.6× improvement
- Power–Delay Product (PDP): ~193× improvement

---

## Accuracy Results

Evaluated on four NLP benchmarks (same hyperparameters as FP32 reference):

| Dataset | Task | FP32 Baseline | Float-Fix | Delta |
|---------|------|--------------|-----------|-------|
| UDPOS | POS Tagging (Acc %) | 89.43 | 86.43 | −3.0% |
| SNLI | NLI (Acc %) | 77.79 | 75.95 | −1.8% |
| Multi30K | LM (Perplexity ↓) | 48.79 | 48.25 | −0.54 |
| WikiText-2 | LM (Perplexity ↓) | 248.38 | 260.66 | +12.28 |

The 2–3% accuracy gap is offset by over an order-of-magnitude improvement in hardware efficiency, making this architecture suitable for **edge deployment**.

---

## Repository Structure

```
float-fix-lstm/
├── rtl/                        # Synthesizable Verilog RTL
│   ├── q611_to_e3m4.v          # Q6.11 → E3M4 converter
│   ├── lfp_e3m4_multiplier.v   # LFP-E3M4 multiplier
│   ├── e4m4_to_q611.v          # E4M4 → Q6.11 converter
│   ├── lfp_mac.v               # Full LFP MAC unit
│   ├── combinational.v         # LSTM cell (4 gates)
│   ├── sigmoid_lut.mem         # Sigmoid LUT (384 entries)
│   └── tanh_lut.mem            # Tanh LUT (353 entries)
├── sim/                        # Co-simulation testbenches
│   ├── tb_combinational.v      # MAC unit testbench
│   └── check.py                # Python–RTL co-simulation driver
├── training/                   # PyTorch training scripts
│   ├── train_udpos.py
│   ├── train_snli.py
│   ├── train_multi30k.py
│   └── train_wikitext2.py
├── synth/                      # Synthesis scripts (GPDK 45nm)
│   └── synth.tcl
└── README.md
```

---

## Getting Started

### Prerequisites

- Python ≥ 3.8 with PyTorch
- A Verilog simulator (Icarus Verilog, ModelSim, or VCS)
- *(Optional)* Synopsys Design Compiler or Cadence Genus for synthesis

### Install Python dependencies

```bash
pip install torch torchtext numpy
```

### Run the bit-exact Python golden model

```bash
cd python
python float_fix_lstm.py --hidden 128 --seq_len 32
```

### Run RTL–Python co-simulation

```bash
cd sim
python cosim_runner.py --num_tests 1000000
```

This drives randomized weight/input combinations through both the Python model and RTL simulation, asserting bit-exact agreement on all outputs.

### Train on NLP benchmarks

```bash
# Example: WikiText-2 language modeling
cd training
python train_wikitext2.py --epochs 50 --batch_size 64
```

All scripts default to the same hyperparameters as the paper (see Table I).

---

## Numeric Representation Details

### Q6.11 Fixed-Point
- 18-bit two's complement: 1 sign + 6 integer + 11 fractional bits
- Resolution: `Δ = 2⁻¹¹ ≈ 0.000488`
- Max quantization error: `|eq| ≤ 2⁻¹² `
- Used for: inputs `x(t)`, hidden state `h(t)`, cell state `C(t)`

### E3M4 Floating-Point
- 8-bit: 1 sign + 3 exponent + 4 mantissa bits
- Relative rounding error: `|er| ≤ 2⁻⁴`
- Used for: all weight matrices (`Wfx, Wfh, Wix, ...`)

### LFP Multiplication
Mantissa conversion between integer and logarithmic domains uses a 1-bit correction on a 4-bit mantissa (lightweight SOP approximation). Exponent fields are simply added, producing an intermediate E4M4 product before conversion back to Q6.11.

### Activation LUTs
| Function | Entries | Strategy |
|----------|---------|----------|
| Tanh | 176 | Exploit odd symmetry + near-linear region `[0, 0.25)` + saturation |
| Sigmoid | 384 | Exploit symmetry around `(0, 0.5)` + saturation for `\|x\| > 6` |

---

## Citation

If you use this work, please cite:

```bibtex
@article{floatfix_lstm,
  title     = {An Energy--Latency--Area Optimized LSTM Architecture Using Approximate Float--Fix Representation},
  year      = {2025},
}
```

---

## License

All design files (RTL, Python model, testbenches) are freely available for adoption and further usage by designers and the research community.
