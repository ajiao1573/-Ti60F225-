# Canny weak-edge stability candidate audit

Original audit used the unchanged baseline ti60_A_960x720_60fps_noise. Bundled scripts now resolve the containing project for portability; the baseline mathematical oracle and common filters remain unchanged. Recorded JSON hashes refer to the original audit source snapshot.
These are integer software models, not FPGA timing, RTL, resource, or board verification.

## Reproduce

Run evaluate_candidates.py then compare_gaussian_anchor.py using the bundled Python executable:
C:/Users/DELL/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe
No third-party Python packages are required. Outputs are candidate_metrics.json and gaussian_anchor_metrics.json in this directory. The first JSON records SHA256 of the product source read during this audit.

## Model and metrics

48x32,16 frames/scene, THR27, Canny+Median. Product common RGB smoothing, adaptive second pass, median, and two rounded Gaussian passes are retained. Baseline classifications and final edge pixels match the existing current integer oracle for176 frames. The follow-up changes only the Canny Gaussian loop count for its one-pass counterfactual.

Seed is99241 plus the sum of scene-name character codes. Weak contours use gray96 plus contrast12/16/24 (steps), contrast24/48 (one-pixel lines), or contrast24 (two-pixel vertical/diagonal line), with independent uniform +/-4 noise. Flat scenes use128 with uniform +/-12 or +/-24 noise. Moving scene is a40/200 step moving one pixel/frame. Disappear scene removes a contrast40 step at frame8.

Rows metric counts a detected pixel within +/-3 columns of the known contour, over frames2..15 and rows5..26:308 possible rows. Flip counts are exact coordinate changes in the interior38x22 region between successive measured frames. Coverage and flip count must be considered together; erasing edges can misleadingly lower flips. Background edges exclude a +/-5-column band near contours. Flat scenes count every interior pixel. Disappear totals count all interior edges from frame8 onward. Moving width and position relative to baseline are separately reported; lower moving flips are not automatically beneficial.

Candidate history is one bit per pixel, previous final class2. Hold requires current mag>=max(low,high-3), both-side weak tangent support, and mag+2>=both normal neighbors. New non-held peaks are suppressed by a normal neighbor with previous history, same current direction/polarity, magnitude>=hold limit, and neighbor mag+2>=center. Held peaks remain class2 and enter next history; they may persist indefinitely while near-threshold current evidence persists. This is Schmitt hysteresis, not a forced one-frame timeout. Clear history validity when threshold/mode changes is an implementation requirement; the model starts each scene with invalid history and does not simulate live switches. Safe_anchor4 additionally requires the competing neighbor itself to meet hold conditions; it matched anchor4 in these fixtures but needs more neighborhood information in RTL.

## Recommendation

Keep two Gaussian passes, Median, and two-hop local linking; evaluate anchor2 in RTL. It substantially reduces position changes on16/24-contrast steps and48-contrast thin lines and improves diagonal coverage. Extending linking to4 alone brings smaller benefits and increased flat24 noise11->15. Reducing Gaussian count increases flat24 background edges11->213 (225 with anchor), so is not recommended as the default.

Limits: contrast24 one-pixel line remains undetected atTHR27 in every variant. Contrast12 shadow coverage improves88/308->218/308 with anchor2, but total flips144->148: recovering more weak points does not eliminate all flicker. Static16-contrast step flips244->101 with unchanged307/308 coverage.24-contrast step coverage288->302 and flips126->59. Two-pixel diagonal coverage282->308 and flips498->236.48-contrast one-pixel line remains308/308 while flips198->2.

Motion cost: anchor2 at1pixel/frame has average0.370pixel lag relative to baseline and worst1pixel lag; all tested rows remain one pixel wide. No tested edges remain in the first fully absent frame. This does not establish a bound for all real scenes or velocities.

Memory planning:960x720 one-bit history is691200 raw bits. Actual block count depends on inferred aspect ratio/port constraints; raw bit division is only a lower bound. Read previous history before overwriting each current-frame position, align its synchronous read with magnitude/direction, write current class2 after NMS, and use accepted-SOP configuration validity so incomplete/configuration-mismatched frames cannot seed later history. Verify gaps, borders, frame abort and mode/threshold switches in RTL.
