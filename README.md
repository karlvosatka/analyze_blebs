# analyze_blebs

A semi-automated bleb analysis plugin for ImageJ / FIJI.

Vosatka, KW et al. (2022)

Version 1.3

Last updated 03-31-2022 by Karl Vosatka

Requires:
- ImageJ v. 1.53d or later
- "ResultsToExcel" Plugin

Changed in v. 1.3
- created findSpeed() function to calculate cell speed
- moved "rate" and "rate_unit" variables to initialize in startUp() instead of previously used "bleb_rate" and "bleb_unit" found only in blebTracker (for speed measurements)
- added avg_speed variable to be reported in as yet untitled summary file
- implemented findSpeed() for cell_body
- added collectAreas() and compareAreas() for creating per-frame normalized area values and bleb counts in a new file, area_comp.csv
- added collectSummaryStats() and linearSearch() for calculating summary statistics for each measurement across cell parts in a new file, summary_stats.csv
- removed ImageJ summary files from plugin outputs that are now redundant to above
- corrected bug to zoomChecker() triggered by starting plugin with more than 2 images open
