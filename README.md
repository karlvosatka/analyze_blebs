# analyze_blebs

Analyze_Blebs\n
A semi-automated bleb analysis plugin for ImageJ / FIJI.\n
Vosatka, KW et al. (2021)\n
Version 1.2\n
Last updated 11-08-2021 by Karl Vosatka\n\n

Requires:
- ImageJ v. 1.53d or later
- "ResultsToExcel" Plugin

Changed in v. 1.2:
- Autozoom and auto positiong feature added to change window size and reorient windows and prevent overlap (zoomFinder(), zoomChecker())
- Added toggles for size gates, auto positioning feature, and window orientation feature to plugin options
- Added set to defaults option in plugin options
- Changed thickness of lines relative to image scale
- Limited autoscan for multiple cells per frame to cases where multicells are suspected

