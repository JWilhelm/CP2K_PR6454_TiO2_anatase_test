# CP2K PR #6454: test with TiO2 anatase (GW band structure, 12x12x12 k mesh)

Inputs and outputs of a test of [cp2k/cp2k#6454](https://github.com/cp2k/cp2k/pull/6454)
(generic RSKP transform, GEMM and lattice-FFT backends) on a larger periodic system:
TiO2 anatase, 12 atoms in the unit cell, aug-SZV-MOLOPT-GTH-tier-2 basis (208 basis functions),
Monkhorst-Pack 12x12x12 k mesh (1728 k points), PBE SCF followed by a periodic RI-RS GW
band structure (G0W0 and evGW0).

## Code versions

| Label | Commit | Description |
|---|---|---|
| master | `f37a53adbd` | merge base of PR #6454 with master |
| PR | `611fbac9ee` | head of PR #6454 (`RTChou67:unify-lattice-fft`) |

Both were built identically (Release, GCC 14.3 / gfortran, OpenMPI and OpenBLAS 0.3.30 from
`foss/2025b`, FFTW3 with OpenMP, DBCSR 2.10, libint 2.11, libxc 7.1).

## Hardware and layout

Noctua 2 (Paderborn), 2x AMD EPYC 7763 per node: 128 cores and 256 GB RAM per node (`normal`), 2 TB RAM per node on `hugemem` (used for the 1-node runs).
All runs use 16 MPI ranks x 8 OpenMP threads per node (`OMP_NUM_THREADS=8`), see `run.sbatch`.

## Runs

| Run | Code | `RSKP_TRANSFORM` | Nodes | Result |
|---|---|---|---|---|
| `runs/SZ2_base_4n` | master | (`LATTICE_FFT` default) | 4 | completes, 2849 s total |
| `runs/SZ2_pr_4n` | PR | GEMM (default) | 4 | SIGSEGV in GW (Σx step) after 10.5 min |
| `runs/SZ2_pr_1n` | PR | GEMM (default) | 1 | SIGSEGV at the same place |
| `runs/SZ2_prg_4n` | PR, built with `-g -fbacktrace` | GEMM (default) | 4 | same SIGSEGV, backtrace in `cp2k.stderr` |
| `runs/SZ2_prfft_4n` | PR | FFT | 4 | abort in the first SCF step |

The only input difference between the runs is the line `RSKP_TRANSFORM FFT` in `&KPOINTS` for
`SZ2_prfft_4n`.

### 1. `RSKP_TRANSFORM FFT`: abort in the SCF

```
R-to-K route is incompatible or forced FFT exceeds the memory budget   (qs_kpoint_operators.F:328)
kpoint_operator_prepare <- do_general_diag_kp <- qs_scf_new_mos_kp <- scf_env_do_scf_inner_loop
```

### 2. `RSKP_TRANSFORM GEMM` (default): SCF fine, GW slower, then SIGSEGV

The SCF gives the same total energy as master (-361.770793768 Ha). In the GW part:

| Step (4 nodes) | master | PR (GEMM) |
|---|---|---|
| RI-RS grid optimization | 6.2 s | 6.3 s |
| d_lP numerical integration | 75.0 s | 76.1 s |
| Z_lP(q) | 86.7 s | 87.9 s |
| χ(iτ), per time point | 11.9–12.6 s | 27.9–30.9 s |
| W(iω), per frequency point | 2.0–2.2 s | 2.0–2.1 s |
| Σx | completes | SIGSEGV |

The time points of χ are processed in parallel time groups, so the per-point times are the
numbers to compare. On one node, χ(iτ) takes 89–94 s per time point with master and
235–254 s with the PR.

The χ step is about 2.4x slower with the PR. In master, the k → R transform in χ uses the
lattice FFT (`gw_k_grid_to_real_cells`, `cell_to_k_grid_fft`); the PR's GEMM path in
`k_to_real_cell_transform` / `cell_to_k_transform` forms the full phase sum over all
1728 k points and all lattice cells for every matrix element, which scales as N_k^2 per element.

The crash (all 64 ranks, same backtrace, `runs/SZ2_prg_4n/cp2k.stderr`):

```
#0  in ???
#1  in __kpoint_transform_MOD_cell_to_k_transform
#2  in product_to_k_pair_centered
#3  in self_energy_on_mesh
#4  in compute_sigma_x_from_v
#5  in __gw_ri_rs_small_cell_full_kp_utils_MOD_compute_sigma_x
#6  in __gw_ri_rs_small_cell_full_kp_MOD_gw_calc_ri_rs_small_cell_full_kp
#7  in __gw_MOD_run_gw
```

`self_energy_on_mesh` passes chunks of at most 64 MiB of Σ(R) (`chunk(1:n_pairs, :, :)`) to
`product_to_k_pair_centered`, which calls `cell_to_k_transform` with the native 12x12x12 mesh.
The same routine `product_to_k_pair_centered` runs through in the χ step, where it gets the full
array and the q mesh.

## How to rerun

1. Unpack the SCF restart file into the run directory:
   `gunzip -c TiO2_anatase_sz2_2n-RESTART.kp.gz > TiO2_anatase_sz2_2n-RESTART.kp`
   (with `SCF_GUESS ATOMIC` instead of `RESTART` the SCF also works, it just takes longer).
2. `BASIS_AUG_MOLOPT_GTH` and `GTH_POTENTIALS` are the files from `cp2k/data`.
3. Run `cp2k.psmp -i input.inp -o output.out` on 4 nodes with 64 MPI ranks x 8 OpenMP threads.
