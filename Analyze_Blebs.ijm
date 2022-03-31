////
//// Analyze_Blebs
////
//// Semi-automated bleb analysis plugin
//// Vosatka, KW et al. (2022)
//// Version 1.3
//// Last updated 03-31-2022 by Karl Vosatka
//// 
//// 
//// Requires 
//// -ImageJ v. 1.53d or later
//// -"ResultsToExcel" Plugin
////
//// Changed in v. 1.2:
//// - Autozoom and auto positiong feature added to change window size and reorient windows and prevent overlap (zoomFinder(), zoomChecker())
//// - Added toggles for size gates, auto positioning feature, and window orientation feature to plugin options
//// - Added set to defaults option in plugin options
//// - Changed thickness of lines relative to image scale
//// - Limited autoscan for multiple cells per frame to cases where multicells are suspected
//// 
//// v 1.2.1
//// - added comments
//// - changed setmeasures variable collection from dialog box for clarity
//// - fixed bug that would reset zoom improperly if image is initially at the correct zoom range
//// - fixed bug where name of excel sheet in summary excel file does not change to reflect the name entered by user during startUp().
////
//// v 1.3
//// - created findSpeed() function to calculate cell speed
//// - moved "rate" and "rate_unit" variables to initialize in startUp() instead of previously used "bleb_rate" and "bleb_unit" found only in blebTracker (for speed measurements)
//// - added avg_speed variable to be reported in as yet untitled summary file
//// - implemented findSpeed() for cell_body
//// - added collectAreas() and compareAreas() for creating per-frame normalized area values and bleb counts in a new file, area_comp.csv
//// - added collectSummaryStats() and linearSearch() for calculating summary statistics for each measurement across cell parts in a new file, summary_stats.csv
//// - removed ImageJ summary files from plugin outputs that are now redundant to above
//// - corrected bug to zoomChecker() triggered by starting plugin with more than 2 images open
//// 
//// 

var source = "";
var og_source = "";
var data_name = "";
var sub_name = "";
var extension = "";
var chosen_threshold = "";
var avg_speed = 0
var skip_count = 0;
var num_cells = 1;
var first_slice = 1;
var last_slice = 1;
var interval = 1;
var tracer_id = "";
var rest_of_name = "";
var pick_measures = false;
var db_x = 0;
var db_y = 0;
var db_w = 0;
var zoom = 0;
var line_w = 0;
var cb_size = "";
var sizes = newArray(0, 0);
var left = newArray(4);
var right = newArray(4);

var prev_settings = call("ij.Prefs.get", "blebs.prev_settings", false);
var leader_bleb = call("ij.Prefs.get", "blebs.leader_bleb", true);
var indiv_bleb = call("ij.Prefs.get", "blebs.indiv_bleb", false);
var rate = call("ij.Prefs.get", "blebs.rate", 1);
var rate_unit = call("ij.Prefs.get", "blebs.rate_unit", "Seconds");
var z_choice = call("ij.Prefs.get", "blebs.z_choice", "Select a single Z plane");
var z_proj = call("ij.Prefs.get", "blebs.z_proj", "projection=[Maximum Intensity]");
var MPP = call("ij.Prefs.get", "blebs.MPP", "");
var choose_xls = call("ij.Prefs.get", "blebs.choose_xls", false);
var expt_excel = call("ij.Prefs.get", "blebs.expt_excel", "");
var pick_measures = false;
var measures = call("ij.Prefs.get", "blebs.measures", "area centroid perimeter shape feret's stack decimal=3");
var measure_bstr = call("ij.Prefs.get", "blebs.measure_bstr", "1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0");
var invert_check = call("ij.Prefs.get", "blebs.invert_check", false);
var bleb_size = call("ij.Prefs.get", "blebs.bleb_size", 10);
var cell_size = call("ij.Prefs.get", "blebs.cell_size", 200);
var handed = call("ij.Prefs.get", "blebs.handed", "1, 1, 1, 1");
var auto_pos = call("ij.Prefs.get", "blebs.auto_pos", true);

//Make sure an image is open
while(true) {
	if(nImages == 0) {
		//Dialog - Asks user to choose an image file to open if one is not currently open.
		Dialog.create("Open an Image Series");
		Dialog.addMessage("Please select an image time series for analysis");
		Dialog.addFile("", "");
		Dialog.show();

		open(Dialog.getString());
	}
	else break;
}

//Find values used throughout plugin that are dependent on image scale
getDimensions(width, height, channels, slices, frames);
zoomFinder(); //finds the appropriate zoom for the actively selected image series
trash = zoomChecker(true); //fills the sizes array in memory
lineWidth(); //calculates proper line width based on image series
last_slice = frames; //set last_slice in memory to be the length of the time lapse

//Decide if running multiple cells
mult = startUp();
if(mult) {

	
	images = getList("image.titles");
	//Dialog - indicate settings for multiple cell analysis
	Dialog.createNonBlocking("Cells");
	Dialog.addNumber("Number of cells to analyze: ", 1);
	Dialog.addMessage("Cells are labelled from 1 by default");
	Dialog.addCheckbox("Use custom labels", false);
	Dialog.show();
	
	num_cells = Dialog.getNumber();
	custom_label = Dialog.getCheckbox();
	labels = newArray(num_cells);

	if(custom_label) {
		//Dialog - choose a custom label to append to each of multiple cells for naming files
		Dialog.createNonBlocking("Labels");
		Dialog.addMessage("Enter your label for each cell");
		//loop to add an entry to the DB for each label based on number of cells indicated
		for(i=0;i<labels.length;i++) {
			Dialog.addString("Label " + i + 1, "");
		}
		Dialog.show();
		
		//loop to record choices of labels
		for(i=0; i<labels.length;i++) {
			labels[i] = Dialog.getString();
		}
	}
	else { //default label is numbers starting from 1
		for(i=0; i<labels.length; i++) {
			labels[i] = i + 1;
		}
	}
	window_name = getTitle();
	rest_of_name = substring(window_name, lengthOf(data_name));
	batch_names = newArray(num_cells); 
	batch_sources = newArray(num_cells); 
	//loop to store full names for each cell to be measured, create a folder for each, and store that folder location for saving
	for(i=0; i < num_cells; i++) {
		batch_names[i] = data_name + "_" + labels[i]; //store a name for each of the multi cells
		batch_sources[i] = source + File.separator + batch_names[i] + File.separator; //store a source name to save each cell
		File.makeDirectory(batch_sources[i]); //create directories for each cell 
	}
	run("Set... ", "zoom=" + zoom*100);
	getSkips();
	rawToThresh(true);
	multiThresh();
}

else {
	rawToThresh(false);
	cellPartition(false);
}
close("*");

waitForUser("Finished", "Analysis of this file is complete!");
exit();

//doNaming() stores the unaltered root name of the original file in memory for use throughout the plugin. It also
//handles each permitted case where the plugin is used with a plugin output file.
function doNaming() {
	//data_name = get just the file name, no extension (i.e. no .tif, no .dv)
	data_name = File.getNameWithoutExtension(source + getTitle());
	extension = substring(getTitle(), lengthOf(data_name));
	if (endsWith(data_name, ".tif")) { //remove 
		data_name = substring(data_name, 0, lastIndexOf(data_name, "."));
	}
	//check the name to see if it is a threshold image (it would therefore have the method in the filename)
	if (indexOf(data_name, "method") >= 0) { 
		//if so, store the name of the threshold that was used as chosen_threshold for later reference
		chosen_threshold = substring(data_name, lastIndexOf(data_name, "method"), lengthOf(data_name));
		data_name = substring(data_name, 0, lastIndexOf(data_name, "_method"));
	}
	//check if the image is any other macro-generated image besides threshold by looking for plugin-added suffixes in the name
	if (endsWith(data_name, "_all_blebs")||endsWith(data_name, "_whole_cell")||endsWith(data_name, "_largest_bleb")) {
		//if so, remove those suffixes for the true file name
		data_name = substring(data_name, 0, lastIndexOf(data_name, "_"));
		data_name = substring(data_name, 0, lastIndexOf(data_name, "_"));
	}
	
	if (endsWith(data_name, "_threshold")||endsWith(data_name, "_tracer")) {
		data_name = substring(data_name, 0, lastIndexOf(data_name, "_"));
	}
	//remove spaces, for compatibility with Linux
	data_name = replace(data_name, " ", "_");
	//once data_name is fully isolated, create a copy that is within 30 characters. this is needed for naming Excel sheets
	//in the Excel export steps.
	sub_name = data_name;
	if (lengthOf(data_name) >= 31) {
		sub_name = substring(data_name, lengthOf(data_name) - 30);
	}
}

//startUp() guides the user through a series of dialogs to confirm required settings, and ensures that any multi-stack image is isolated to a time-stack only.
function startUp() {
	getSkips();
	source = getInfo("image.directory"); //store the location of the original file in memory
	og_source = source;
	doNaming(); //store the name of the original file in memory
	resetMinAndMax;
	run("Enhance Contrast", "saturated=0.35");
	run("Set... ", "zoom=" + zoom*100);
	run("Input/Output...", "jpeg=85 gif=-1 file=.csv use_file copy_column copy_row save_column save_row"); //standardize output settings 
	
	//Dialog - Initial dialog, collects info for file naming/saving as well as various plugin options
	Dialog.createNonBlocking("Startup Options");
	Dialog.addMessage("Enter the label you would like added to each data file and choose the folder to save plugin outputs\nNote: All spaces for data file names will be replaced with underscores");
	Dialog.addString("Data File Name:", data_name, 30); //decide on naming of plugin output files
	Dialog.addDirectory("Data File Folder:", source); //decide on saving location
	Dialog.addCheckbox("Add data to an excel file for the experiment (recommended)", choose_xls); //decide on auto-excel export
	Dialog.addFile("Excel File Location:", expt_excel); //find and choose Excel file
	Dialog.addCheckbox("Analyze Leader Bleb", leader_bleb);
	Dialog.addCheckbox("Individual Bleb Analysis", indiv_bleb);
	if (skip_count == 0) { //If starting from raw data file, isolate to time stack
		Dialog.addCheckbox("Use previous image formatting options (Z isolation, micron conversion)", prev_settings);
	}
	if (skip_count <3) { //Give option to analyze multiple cells, unless working with an all_blebs image
		Dialog.addCheckbox("Analyze multiple cells on the same image", false);
	}	
	
	Dialog.addMessage("\nTime Series Settings");
	units = newArray("Milliseconds", "Seconds", "Minutes");
	Dialog.addNumber("Frame Rate: ", rate, 0, 3, "time units per frame"); 
	Dialog.addRadioButtonGroup(" Time Unit:", units, 1, 3, rate_unit);
	
	Dialog.addMessage("");
	Dialog.addCheckbox("Access Plugin Options", pick_measures); //decide on whether or not to configure measurement outputs
	
	Dialog.show();
	
	entered_name = Dialog.getString();
	source = Dialog.getString();;
	if (indexOf(entered_name, " ") >= 0) {
		entered_name = replace(entered_name, " ", "_");
	}
	if(data_name != entered_name) {
		window_id = getImageID();
		window_name = getTitle();
		window_name = replace(window_name, data_name, entered_name); //replaces the chosen part of the name while keeping the cell part name (e.g. _threshold) in place
		selectImage(window_id);
		rename(window_name);
		if(skip_count > 1) {
			saveAs("tiff", source + window_name); //if re-running plugin, output file is saved, so that a new name can be reflected
		}
		if (lengthOf(entered_name) >= 31) {
			sub_name = substring(entered_name, lengthOf(entered_name) - 30);
		}
	}
	data_name = entered_name;
	expt_excel = Dialog.getString();
	choose_xls = Dialog.getCheckbox();
	leader_bleb = Dialog.getCheckbox();;
	indiv_bleb = Dialog.getCheckbox();;;
	if(skip_count == 0) {
		prev_settings = Dialog.getCheckbox();;;;
		call("ij.Prefs.set", "blebs.prev_settings", prev_settings);
	}
	if (skip_count < 3) {
		mult = Dialog.getCheckbox();;;;
	}
	else {
		mult = false;
	}
	pick_measures = Dialog.getCheckbox();;;;;
	
	rate = Dialog.getNumber();
	rate_unit = Dialog.getRadioButton();
	
	call("ij.Prefs.set", "blebs.rate", rate);
	call("ij.Prefs.set", "blebs.rate_unit", rate_unit);


	//Excel Experimental File Logic
	//Confirms that the file chosen in the initial dialog under the Experimental Excel section is actually an Excel file.
	//A tab will created and labelled with the name of the cell being analyzed within the Excel file chosen.
	if(choose_xls) {
		i = 0;
		//Loop: Ensure Excel File is chosen. Will run until experimental excel file is chosen or user chooses to forgo expt'l excel
		while (i == 0) {
			if (endsWith(expt_excel, ".xls")||endsWith(expt_excel, ".xlsx")) {
				i = 1;
			}
			
			else {
				//Dialog - re-choose an experiment-level Excel file, or choose to forgo that option
				Dialog.create("Experimental Excel File Warning");
				Dialog.addMessage("You didn't select an excel file from this experiment to save this cell (.xls or .xlsx)");
				Dialog.addFile("Excel File Location: ", expt_excel); //find and choose Excel file
				oops_excel = newArray("Excel file chosen", "I don't want an experimental Excel file");
				Dialog.addRadioButtonGroup("", oops_excel, 2, 1, oops_excel[0]);
				Dialog.show();
	
				if(Dialog.getRadioButton() == "I don't want an experimental Excel file") {
					choose_xls = false;
					i = 1;
				}
			}
		}
	}
	
	call("ij.Prefs.set", "blebs.choose_xls", choose_xls);
	call("ij.Prefs.set", "blebs.expt_excel", expt_excel);
	call("ij.Prefs.set", "blebs.leader_bleb", leader_bleb);
	call("ij.Prefs.set", "blebs.indiv_bleb", indiv_bleb);
	
	if(skip_count == 0) {

		//// Color channels automatically split with user choosing preferred color for analysis
		if(channels > 1) { //if the data is a multi-color stack...
			//Select the color channel for analysis
			window_name = getTitle();
			new_windows = newArray(channels);
			resetMinAndMax;
			run("Split Channels");
			//loop to store each channel window's name for later drop-down selection menu
			for(i = 0; i < channels; i++) {
				selectWindow("C" + (i + 1) + "-" + window_name);
				new_windows[i] = getTitle();
				
				run("Enhance Contrast", "saturated=0.35");
				run("Set... ", "zoom=" + zoom*100);
			}
			
			//Dialog - choose preferred color channel
			Dialog.createNonBlocking("Color Channel");
			Dialog.addMessage("Choose your preferred color channel");
			Dialog.addChoice("", new_windows);
			Dialog.setLocation(getDbX(), (screenHeight/2-200));
			Dialog.show();
			
		    chosen_name = Dialog.getChoice();
		    //loop to close all windows except for the one with chosen_name
		    for(i = 0; i < channels; i++) {
		    	selectWindow("C" + (i + 1) + "-" + window_name);
		    	if(getTitle() != chosen_name) {
		    		close();
		    	}
		    }
		    selectWindow(chosen_name);
		}
		//// Z-slices automatically detected and isolated either by collapsing Z planes or by selecting a single plane
		if (slices > 1 && slices != nSlices) { //if the image has multiple Z planes...
			
			//Choose your preferred method for isolating one Z frame
			if (!prev_settings) { //You only get this choice if you chose not to use previous settings.
				//Dialog - select Z method desired for isolating planes
				Dialog.createNonBlocking("Z Stack Method");
				Dialog.addMessage("Select the preferred method for isolating Z plane");
				z_options = newArray("Select a single Z plane", "Collapse Z planes");
				Dialog.addRadioButtonGroup("", z_options, 2, 1, z_options[0]);
				Dialog.setLocation(getDbX(), (screenHeight/2-200));
				Dialog.show(); 
				z_choice = Dialog.getRadioButton();
			}
			
			//Single Z Plane method
			if(z_choice == "Select a single Z plane") { //if you want to choose a single Z plane...
				window_name = getTitle();
				new_windows = newArray(slices); 
				resetMinAndMax;
				run("Deinterleave", "how=" + slices); //...automatically split by number of slices on the image...

				//Loop to store names of each slice window, and standardize contrast and window size
				for(i = 0; i < slices; i++) {
					selectWindow(window_name + " #" + (i + 1));
					new_windows[i] = getTitle();
					
					run("Enhance Contrast", "saturated=0.35");
					run("Set... ", "zoom=" + zoom*100);
				}

				//Dialog - choose desired z slice based on its window name
				Dialog.createNonBlocking("Z plane");
				Dialog.addMessage("Choose your preferred Z plane");
				Dialog.addChoice("", new_windows);
				Dialog.setLocation(getDbX(), (screenHeight/2-200));
				Dialog.show();
				
				chosen_name = Dialog.getChoice();
				//Loop to close all non-chosen windows without closing any background windows that are open.
				for(i = 0; i < slices; i++) {
					selectWindow(window_name + " #" + (i + 1));
					if(getTitle() != chosen_name) {
						close();
					}
				}
				selectWindow(chosen_name);
			}

			//Z Plane Collapse method
			else if(z_choice == "Collapse Z planes") { //if you want to combine all Z planes into one stacked image...
				if(!prev_settings) { //only show choice if you don't want to use previous settings as indicated in startup
					
					//Dialog - select from ImageJ's standard Z-collapsing options, and enter the range of Z planes you would like to collapse
					Dialog.createNonBlocking("Z-Projection");
					Dialog.addNumber("Start slice:  ", 1);
					Dialog.addNumber("Stop slice:  ", slices);
					z_proj_options = newArray("Average Intensity", "Max Intensity", "Min Intensity", "Sum Slices", "Standard Deviation", "Median");
					Dialog.addChoice("Projection Type  ", z_proj_options, z_proj_options[1]);
					Dialog.setLocation(getDbX(), (screenHeight/2-200));
					Dialog.show();
					
					z_start = Dialog.getNumber();
					z_stop = Dialog.getNumber();;
					z_method = Dialog.getChoice();
					z_proj = "start=" + z_start + " stop=" + z_stop + " projection=[" + z_method + "] all";
				}
				window_name = getTitle();
				resetMinAndMax;
				run("Z Project...", z_proj);
				close(window_name);
				
				run("Enhance Contrast", "saturated=0.35");
				run("Set... ", "zoom=" + zoom*100); 
				if (bitDepth() == 32) { //to move forward, images have to be 16-bit. This will run a conversion if the method you chose produces a 32-bit image (eg. in Sum Slices)
					setMinAndMax(0, 65535); //bins intensities to 16-bit depth
					run("16-bit");
				}
			}
		}
		
		call("ij.Prefs.set", "blebs.z_proj", z_proj);
		call("ij.Prefs.set", "blebs.z_choice", z_choice);

		//// Pixel Size Conversion (automatically triggered as needed)
		getPixelSize(unit, pw, ph);
		if (unit == "pixels"||pw == 1) { //if the image is not scaled properly in microns...
			//...convert image to microns
			if(!prev_settings||MPP == "") { //You only have to enter your conversion rate if you chose to do so earlier or if you have yet to enter your conversion rate previously
				//Dialog - enter size of each pixel in microns as determined by microscope image sensor
				Dialog.create("Convert to microns");
				Dialog.addNumber("Conversion:", MPP, 4, 6, getInfo("micrometer.abbreviation") + "/pixel");
				Dialog.show(); //enter the conversion rate of your microscope in microns/pixel. this information is associated with the chip on your microscope.
				MPP = Dialog.getNumber();
			}
			run("Set Scale...", "distance=1 known=MPP pixel=1 unit=micron");
		}
		call("ij.Prefs.set", "blebs.MPP", MPP); //save your conversion rate for later use
		rename(data_name + "_tracer.tif");
	}

	return mult;
}

//// getDbX retrieves the proper location of the dialog box relative to the left-hand window on screen, placing it to the right side of it with a small gap.
function getDbX() {
	getLocationAndSize(ix, iy, iw, ih);
	pop_up = ix + iw + screenHeight/30;
	return pop_up;
}

//// sliceKeeper recreates the function of the "Slice Keeper" tool in ImageJ, allowing the user to pick a slice range to keep and an interval (i.e. every nth frame) to keep.
//It involves an added message suited to the moment it is called referring to isolation of a bleb or of an object in general. It also adds a function using the "all" boolean
//input that will repeat the slice-keeping step for every window open if all==true, or only for the chosen window if all==false.
//Finally, it renames the window with the name of the original window to bypass the automatic renaming done by ImageJ when using their version of Slice Keeper.
function sliceKeeper(all, type) {
		//Dialog - find first and last desired frames with interval to keep
		Dialog.createNonBlocking("Select Relevant Frames");
		if(type == "bleb") {
			Dialog.addMessage("Enter the slice range/time frame for this bleb");
		}
		else {
			Dialog.addMessage("Enter the slice range/time frame of interest"); //use this to eliminate frames where the cell isn't present or has died
		}
		Dialog.addNumber("First Slice", first_slice);
		Dialog.addNumber("Last Slice", nSlices);
		Dialog.addNumber("Increment", interval); //e.g. keep every 2nd frame, every 3rd frame, etc.
		Dialog.show();
	
		first_slice = Dialog.getNumber();
		last_slice = Dialog.getNumber();;
		interval = Dialog.getNumber();;;

		//if all==false aka only the chosen window should apply the same slice range 
		if (!all) {
			window_name = getTitle();
			run("Slice Keeper", "first=" + first_slice +" last=" + last_slice + " increment=" + interval);
			
			close(window_name);
			run("Set... ", "zoom=" + zoom*100);
			rename(window_name);
		}
		//if all==true, isolate chosen slice range on all open images
		else {
			images = getList("image.titles");
			//loop to apply the same frame range to all open images if the all input of this function is true
			for (i = 0; i < images.length; i++) {
				selectWindow(images[i]);
				window_name = getTitle();
				run("Slice Keeper", "first=" + first_slice +" last=" + last_slice + " increment=" + interval);
				
				close(images[i]);
				run("Set... ", "zoom=" + zoom*100);
				rename(images[i]);
			}
			
		}
}

//// tracerFinder() checks to see if the tracer image is open, tries to find it by searching the main file directory, and if that fails asks user to open it
function tracerFinder() {
	// Loop checks all images repeatedly until the tracer is found, and if not, prompts user to open it
	while(true) {
		//Tracer Scan
		images = getList("image.titles");
		tracer_check = false;
		tracer_id = "";
		//loop to scan through all open images and check if their title includes the word tracer
		for(i = 0; i<images.length; i++) { 
			if(indexOf(images[i], "tracer") >= 0) { //check all image titles for the word tracer
				tracer_check = true;
				selectWindow(images[i]);
				tracer_id = getImageID();
			}
		}

		//if tracer's not open...
		if(!tracer_check) { 
			//...first try to find it in user-chosen source for saving new files and open it
			if(File.exists(source + File.separator + data_name + "_tracer.tif")) {
				open(source + File.separator + data_name + "_tracer.tif");
			}
			//...then tries to find it in the source of the original file that was opened at the start of the plugin
			else if(File.exists(og_source + File.separator + data_name + "_tracer.tif")) {
				open(og_source + File.separator + data_name + "_tracer.tif");
				saveAs("tiff", source + data_name + "_tracer.tif");
			}
			//...and failing either of those, asks the user to find it
			else {
				//Dialog - locate tracer file to open it
				Dialog.createNonBlocking("Open Tracer File");
				Dialog.addMessage("Please select the tracer file for this experiment.");
				Dialog.addFile("", "")
				Dialog.show();
				open(Dialog.getString());
			}
		}
		
		//when tracer is open...
		else { 
			selectImage(tracer_id);
			run("Set... ", "zoom=" + zoom*100);
			//store its name
			tracer_name = substring(getTitle(), 0, indexOf(getTitle(), "_tracer"));
			//if the tracer has a different name for some reason...
			if(tracer_name != data_name) {
				rename(data_name + "_tracer.tif"); //...change its name to match the chosen data_name
				saveAs("tiff", source + data_name + "_tracer.tif"); //...and resave the altered version in the chosen source for reference
			}
			break;
		}
	}
}

//getSkips() scans all open images looking for plugin output images. It alters the skip_count variable, which controls at which point to start in the plugin process, based on the open images.
function getSkips() {
	images = getList("image.titles");
	all_check = false;
	whole_check = false;
	thresh_check = false;
	tracer_check = false;

	//loop to check for plugin output windows and standardize window appearance
	for(i = 0; i<images.length; i++) {
		run("Select None");
		if(zoom != getZoom()) {
			run("Set... ", "zoom=" + zoom*100);
		}
		resetMinAndMax;
		run("Enhance Contrast", "saturated=0.35");
		//for each image type, confirm appropriate _check boolean for setting skip count later and store the image ID for the desired image to set it at the front of view
		if(endsWith(images[i], "_all_blebs.tif")) {
			all_check = true;
			selectWindow(images[i]);
			id_blebs = getImageID();
		}
		else if(endsWith(images[i], "_whole_cell.tif")) {
			whole_check = true;
			selectWindow(images[i]);
			id_main = getImageID();
		}
		else if(indexOf(images[i], "_threshold") >= 0) {
			thresh_check = true;
			selectWindow(images[i]);
			id_main = getImageID();
		}
		else if(indexOf(images[i], "tracer") >= 0) {
			tracer_check = true;
			selectWindow(images[i]);
			tracer_id = getImageID();
		}
	}

	//logic for which window should be selected once the skips have been determined, as we move into main plugin language
	if(all_check) {
		skip_count = 4;
		selectImage(id_blebs);
	}
	else if(whole_check && !all_check) {
		skip_count = 3;
		selectImage(id_main);
	}
	else if(thresh_check) {
		skip_count = 2;
		selectImage(id_main);
	}
	else if(tracer_check && !all_check && !whole_check && !thresh_check) {
		selectImage(tracer_id);
		close("\\Others");
		skip_count = 1;
	}
}

//// invertChecker checks pixel intensity in each corner to see if image is properly inverted in case of error. Used mainly for troubleshooting purposes to ensure that the appropriate
//pixel values are present. This invert check can be toggled in settings.
function invertChecker(window) { 
	selectWindow(window);
	//upper left corner 2x2 rectangle minimum pixel illumination value collected
	makeRectangle(0,0,2,2);
	getStatistics(area,mean,min);
	up_left = min;
	
	//upper edge 2x2 rectangle minimum pixel illumination value collected
	makeRectangle(width/2-1, 0, 2,2);
	getStatistics(area,mean,min);
	up = min;

	//upper right corner 2x2 rectangle minimum pixel illumination value collected
	makeRectangle(width-2,0,2,2);
	getStatistics(area,mean,min);
	up_right = min;

	//left edge 2x2 rectangle minimum pixel illumination value collected
	makeRectangle(0, height/2-1,2,2);
	getStatistics(area,mean,min);
	left = min;

	//right edge 2x2 rectangle minimum pixel illumination value collected
	makeRectangle(width-2,height/2-1,2,2);
	getStatistics(area,mean,min);
	right = min;

	//bottom left corner 2x2 rectangle minimum pixel illumination value collected
	makeRectangle(0,height-2,2,2);
	getStatistics(area,mean,min);
	bottom_left = min;

	//bottom edge 2x2 rectangle minimum pixel illumination value collected
	makeRectangle(width/2-1,height-2,2,2);
	getStatistics(area,mean,min);
	bottom = min;

	//bottom right corner 2x2 rectangle minimum pixel illumination value collected
	makeRectangle(width-2,height-2,2,2);
	getStatistics(area,mean,min);
	bottom_right = min;
	
	run("Select None");

	//make array for all 8 rectangles checked, and see if more than half of them come up with pixel values above 0
	corners = newArray(up_left,up,up_right,left,right,bottom_left,bottom,bottom_right);
	corners_num=0;
	//loop to check each corner's color and add to corners_num if corner has value 0
	for(i=0;i<8;i++) {
		if(corners[i] == 0) {
			corners_num++;
		}
	}

	//if more than half of these corners came up with signal (i.e. they were listed as having an object there), it's likely that the image needs to be inverted and the background is set as 255 (i.e as having signal).
	if(corners_num < 4) {
	run("Invert", "stack");
	waitForUser("The plugin detected an inversion error. \nIf the cell doesn't show up as black on a white background, run Edit>Invert, then continue");
	}
}

//// sizeExclusion() creates a dialog used repeatedly in the plugin to ask the user to indicate the desired size cutoff for the analysis of objects in a binary image
function sizeExclusion(type, default_size, num_label) {
	//Dialog - indicate minimum size cut off for analysis, partly to prevent noise from interfering in data collection
	Dialog.createNonBlocking("Minimum Size Cut-Off For " + type + " Analysis");
	Dialog.addMessage("Enter a size for the " + type.toLowerCase + " in microns squared. All objects below this size will be excluded.\nFor example, for a 60X objective, a size exclusion of 200 microns squared per cell and 10 microns squared per bleb is recommended.");
	Dialog.addMessage("If you don't want to exclude any objects, enter 0.\nHowever, note that noise that is not easily detected by eye may be counted in this case."); //It's highly recommended that you choose a number greater than zero. 
	//In most cases, small artifact objects that are not easily seen by eye will be present on your data file, and if you choose zero as your
	//exclusion size, they will be measured and counted as blebs. The size of 10 microns squared catches even the smallest blebs in most cases.
	Dialog.addNumber(num_label + " Size", default_size);
	Dialog.show();
	
	obj_size = Dialog.getNumber();
	return obj_size
}

//setMeasures() checks and stores the desired measurement output settings for the plugin. If indicated during startUp, setMeasures will allow the user to select different measurement output values as desired and store that information in memory for future
//use of the plugin.
function setMeasures() {
	if (!pick_measures) { 
		//Check if there is a redirect within the measurement input string
		redirect = "";
		if(indexOf(measures, "redirect") >= 0) {
			if(lastIndexOf(measures, " ") < (indexOf(measures, "redirect=") + 9)) { 
				//if the redirect portion of the measures string is the last part of the string,
				redirect = substring(measures, (indexOf(measures, "redirect=") + 9), lengthOf(measures));
				//the stored name of the redirect file will be measured from the end of "redirect=" to the length of measures.
			}
			else {
				redirect = substring(measures, (indexOf(measures, "redirect=") + 9), indexOf(measures, " decimal"));
				//otherwise, take the portion that comes before the decimal label
			}
			measures = replace(measures, redirect, data_name + "_tracer.tif"); 
		}
		else {
			if(lastIndexOf(measures, " ") < (indexOf(measures, "redirect=") + 9))
				measures = substring(measures, 0, indexOf(measures, " decimals")) + " redirect=" + data_name + "_tracer.tif" + substring(measures, indexOf(measures, " decimals"), lengthOf(measures));
		}
		run("Set Measurements...", measures);
		leftAndRight(handed);
	}
	
	else { //If you want to choose your own measures...
		measure_bool = split(measure_bstr, ", ");
		
		//Measure names appear identically to the Analyze>Set Measures... feature in ImageJ.
		//They are accordingly split into separate arrays for ease of reference.
		measure_read = newArray("Area", "Mean gray value", "Standard deviation", "Modal gray value", "Min & max gray value", "Centroid", "Center of mass", "Perimeter", "Bounding rectangle", "Fit ellipse", "Shape descriptors", "Feret's diameter", "Integrated density", "Median", "Skewness", "Kurtosis", "Area fraction", "Stack position", "Limit to threshold", "Display label", "Invert Y coordinates", "Scientific notation", "Add to overlay", "NaN empty cells"); 
		measure_read_a = Array.slice(measure_read, 0, 18);
		measure_bool_a = Array.slice(measure_bool, 0, 18);
		measure_read_b = Array.slice(measure_read, 18, 24);
		measure_bool_b = Array.slice(measure_bool, 18, 24);

		//Dialog - shows all options for plugin. References the "Analyze > Set Measures..." menu. Reference linked to the help button.
		Dialog.create("Plugin Options")
		//First group in measure_read_a: measurement outputs
		Dialog.addMessage("Set Measurements");
		Dialog.addCheckboxGroup(9, 2, measure_read_a, measure_bool_a);
		Dialog.addMessage("\n");
		//Second group in measure_read_b: measurement display and calculation options
		Dialog.addCheckboxGroup(3, 2, measure_read_b, measure_bool_b);
		Dialog.addMessage("\n");
		Dialog.addNumber("Decimal places for measurements (0-9):", 3);
		Dialog.addCheckbox("Invert Check", invert_check);
		Dialog.addMessage("Window Positioning Settings");
		Dialog.addCheckbox("Automatic Positioning", auto_pos);
		handedness = newArray("Right-handed (default)", "Left-handed", "Configure");
		Dialog.addRadioButtonGroup("Window Orientation: ", handedness, 1, 3, handedness[0]);

		//Size gates, used for isolating objects of proper size on thresholded image
		getPixelSize(unit, pw, ph);
		size = (getHeight()*getWidth()*pw*ph)/20; //finds minimum size for cell size on slider, assumed to be 1/20th of frame size (user can always enter a number if lower is desired)
		Dialog.addMessage("Minimum Sizes for Cell Parts");
		Dialog.addSlider("Cell Size", 1, size, cell_size);
		Dialog.addSlider("Bleb Size", 1, size/10, bleb_size); //blebs assumed to be at smallest 1/200th of frame size (user can always enter a number if lower is desired)
		Dialog.addCheckbox("Cell Body Default (0.25 * Cell Size)", true);
		Dialog.addSlider("Cell Body Size", 1, size, 0.25*cell_size);

		Dialog.addCheckbox("Restore Defaults", false);
		Dialog.addHelp("https://imagej.nih.gov/ij/docs/menus/analyze.html#set");
		Dialog.show();
	
		//loops to record chosen measurement outputs as a boolean array
		for (i=0; i<18; i++) {
			measure_bool_a[i] = Dialog.getCheckbox();
		}
		for (i=0; i<6; i++) {
			measure_bool_b[i] = Dialog.getCheckbox();	
		}
		measure_bool = Array.concat(measure_bool_a, measure_bool_b);

		invert_check = Dialog.getCheckbox();
		auto_pos = Dialog.getCheckbox();
		call("ij.Prefs.set", "blebs.auto_pos", auto_pos);

		//Store numbers appropriately
		decimals = Dialog.getNumber();
		cell_size = Dialog.getNumber();
		bleb_size = Dialog.getNumber();
		//If cell body size box is clicked, change size of cell body size cut off
		if(Dialog.getCheckbox()) cb_size = Dialog.getNumber();
		
		hand_choice = Dialog.getRadioButton();
		defaults = Dialog.getCheckbox();

		if(hand_choice == "Right-handed (default)") {
			handed = "1, 1, 1, 1";
		}
		else if (hand_choice == "Left-handed") {
			handed = "0, 0, 0, 0";
		}
		else {
			//Dialog - indicate which window should go on the left side of the screen at the beginning of each tracing step
			Dialog.create("Choose Windows");
			tTrace = newArray("despeckled", data_name + "_tracer.tif");
			tHoles = Array.copy(tTrace);
			tAttached = newArray(data_name + "_threshold_" + chosen_threshold + ".tif", data_name + "_tracer.tif");
			tCB = newArray(data_name + "_tracer.tif", "cell_mask");
			
			Dialog.addMessage("Choose the window that will appear on the left side of the screen by \ndefault during each task. The other window will appear on the right.");
			Dialog.addChoice("Drawing Cell for Threshold", tTrace);
			Dialog.addChoice("Filling Holes", tHoles);
			Dialog.addChoice("Removing Attached Noise", tAttached);
			Dialog.addChoice("Isolating Cell Body", tCB);
			Dialog.show();

			h_choice = newArray((Dialog.getChoice() == tHoles[0]), (Dialog.getChoice() == tAttached[0]), (Dialog.getChoice() == tTrace[0]), (Dialog.getChoice() == tCB[0]));
			handed = String.join(h_choice);
		}
		leftAndRight(handed);
		
		measure_write = newArray("area", "mean", "standard", "modal", "min", "centroid", "center", "perimeter", "bounding", "fit", "shape", "feret's", "integrated", "median", "skewness", "kurtosis", "area_fraction", "stack", "limit", "display", "invert", "scientific", "add", "nan");
		measures = "";
		//loop to create measures string based on user decisions stored in measure_bool
		for(i=0; i<24; i++) {
			if(measure_bool[i]) { //If an option was chosen...
				measures = measures + measure_write[i] + " ";
				//...add the appropriate command word to the measures string
			}
		}
		measures = measures + "redirect=" + data_name + "_tracer.tif decimal=" + decimals; //Add tracer redirect and user input decimals
		run("Set Measurements...", measures);
		pick_measures = false;
		measure_bstr = String.join(measure_bool);
		call("ij.Prefs.set", "blebs.measure_bstr", measure_bstr);
		if(defaults) {
			rate = 1;
			call("ij.Prefs.set", "blebs.rate", rate);
			rate_unit = "sec";
			call("ij.Prefs.set", "blebs.rate_unit", rate_unit);
			z_choice = "Select a single Z plane";
			call("ij.Prefs.set", "blebs.z_choice", "Select a single Z plane");
			z_proj = "projection=[Maximum Intensity]"
			call("ij.Prefs.set", "blebs.z_proj", "projection=[Maximum Intensity]");
			MPP = "";
			call("ij.Prefs.set", "blebs.MPP", MPP);
			measures = "area centroid perimeter shape feret's stack decimal=3";
			call("ij.Prefs.set", "blebs.measures", measures);
			measure_bstr = "1, 0, 0, 0, 0, 1, 0, 1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0";
			call("ij.Prefs.set", "blebs.measure_bstr", measure_bstr);
			invert_check = false;
			call("ij.Prefs.set", "blebs.invert_check", invert_check);
			bleb_size = 10;
			call("ij.Prefs.set", "blebs.bleb_size", bleb_size);
			cell_size = 200;
			call("ij.Prefs.set", "blebs.cell_size", cell_size);
			handed = "1, 1, 1, 1";
			call("ij.Prefs.set", "blebs.handed", handed);
			auto_pos = true;
			call("ij.Prefs.set", "blebs.auto_pos", auto_pos);
			
			call("ij.Prefs.set", "blebs.expt_excel", "");
			call("ij.Prefs.set", "blebs.choose_xls", false);
			
			return;
		}
	}
	
	call("ij.Prefs.set", "blebs.measures", measures);
	call("ij.Prefs.set", "blebs.invert_check", invert_check);
	call("ij.Prefs.set", "blebs.handed", handed);
}



//leftAndRight() allows the user to identify which image they want on either side of the screen as desired during each analysis step (e.g. if the tracer should be on left and cell mask should be on right during cell body isolation step).
//stored as string in memory that is then split to create an array with four binary values, where 1 means right-handed orientation, 0 means left-handed, so that every image in default tracing of design is on the right side for right handed and on left
//for left handed.
//array stores binary decisions as follows: pos[0] = manually draw cell threshold orientation, pos[1] = manually fill holes orientation, pos[2] = remove attached noise manually orientation, pos[3] = identify cell body orientation 

function leftAndRight(str) { //str is an input string with four binary values (i.e. 1 or 0). 1 means right-handed orientation, 0 means left-handed.
	lr = split(str, ", "); //create lr array from str. should have 4 items.
	if(lr[0]) { //manually draw cell threshold orientation handedness 
		left[0] = "despeckled";
		right[0] = data_name + "_tracer.tif";
	}
	else {
		right[0] = "despeckled";
		left[0] = data_name + "_tracer.tif";
	}
	if(lr[1]) { //fill holes orientation handedness 
		left[1] = "despeckled";
		right[1] = data_name + "_tracer.tif";
	}
	else {
		right[1] = "despeckled";
		left[1] = data_name + "_tracer.tif";
	}
	if(lr[2]) { //remove attached noise orientation handedness
		left[2] = data_name + "_threshold_" + chosen_threshold + ".tif";
		right[2] = data_name + "_tracer.tif";
	}
	else {
		right[2] = data_name + "_threshold_" + chosen_threshold + ".tif";
		left[2] = data_name + "_tracer.tif";
	}
	if(lr[3]) { //identify cell body orientation handedness
		left[3] = data_name + "_tracer.tif";
		right[3] = "cell_mask";
	}
	else {
		right[3] = data_name + "_tracer.tif";
		left[3] = "cell_mask";
	}
}

//threshOptions() contains all logic associated with creating a thresholded binary image from the raw tracer file. It calls fillHoles() as needed to correct for holes in mask. It also calls drawCell() if user decides to forgo autothresholding.
//removeNoise() is used later to get whole_cell image
function threshOptions() {
	if(!isOpen("despeckled")) {
		selectWindow(data_name + "_tracer.tif");
		run("Duplicate...", "title=despeckled duplicate");
		run("Set... ", "zoom=" + zoom*100);
	}
	selectWindow("despeckled");
	run("Set... ", "zoom=" + zoom*100);
	setSlice(1);
	
	ThresholdList = newArray("Default", "Huang", "Huang", "Intermodes", "IsoData",
	"Li", "MaxEntropy", "Mean", "MinError", "Minimum", "Moments", "Otsu",
	"Percentile", "RenyiEntropy", "Shanbhag", "Triangle", "Yen", "Drawn"); 
	//note: Huang is listed twice here because, while Huang2 is a potential option that is actually displayed in the second
	//Huang spot on the preview image, the Huang2 option is not available for thresholding. If you like the look of the first
	//Huang option for thresholding, choose that. The second Huang image should be otherwise ignored.
	
	//Auto thresholding
	run("Auto Threshold", "method=[Try all] white");
	run("Set... ", "zoom=12.5 x=2565 y=2084");
	close("Log");
	
	//Label the threshold preview options with the appropriate name
	run("RGB Color");
	setFont("SansSerif" , width/8, "bold");
	setColor(255, 0, 0);
	x=width/16; y=height/8; n = 0;
	//Loops below will draw the appropriate name of each threshold method on the preview image created in the Auto Thresholding step via "Try All"
	while (x < 5*width) {
	    drawString(ThresholdList[n], x, y);
	x += width; n += 1;  }
	x = width/16; y += (33/32)*height;
	while (x < 5*width) {
	    drawString(ThresholdList[n], x, y);
	    x += width; n += 1;  }
	x = width/16; y += (33/32)*height;
	while (x < 5*width) {
	    drawString(ThresholdList[n], x, y);
	    x += width; n += 1;  }
	x = width/16; y += (33/32)*height;
	drawString(ThresholdList[n], x, y);
	x += width; n += 1;
	drawString(ThresholdList[n], x, y);
	x += width; n += 1;
	drawString(ThresholdList[n], x, y);
	rename("threshold options");
	
	// User Decision Loop to re-run threshold until satisfied
	t = 0;
	while (t==0){
		selectWindow("threshold options");
		//Dialog - choose preferred threshold method, should appear between the two image windows
		Dialog.createNonBlocking("Choose your threshold method"); //choose whichever of the preview options you prefer...
		Dialog.addMessage("Choose your preferred thresholding method \nIf not sure, choose Li \nIf none work, choose 'Drawn' to draw cell");
		Dialog.addChoice("Options", ThresholdList, ThresholdList[5]); //...from this drop down menu.
		Dialog.setLocation(getDbX(), (screenHeight/2-200));
		Dialog.show();

		chosen_threshold = "method=" + Dialog.getChoice();
		leftAndRight(handed);
		thresh_loop = "";
		if(chosen_threshold != "method=Drawn") { //assuming you don't want to draw the threshold...
			selectWindow("despeckled");
			run("Duplicate...", "title=thresh_choice duplicate"); //...create a copy of the raw data image....
			selectWindow("thresh_choice");
			run("Convert to Mask", chosen_threshold+" background=Dark calculate"); //...that is converted using your chosen method.
			//This way, you can preview your threshold separate from your original data file before choosing.
			
			
			run("Set... ", "zoom=" + zoom*100);
			
			thresh_rpt = newArray("Try a different threshold", "Draw the whole cell", "Thresholding complete");
			//Dialog - user must check all frames to see if threshold works well
			Dialog.createNonBlocking("Confirm"); 
			Dialog.addMessage("Check all frames for chosen threshold method");
			Dialog.addRadioButtonGroup("", thresh_rpt, 3, 1, thresh_rpt[2]);
			Dialog.setLocation(getDbX(), (screenHeight/2-200));
			Dialog.show();
			thresh_loop = Dialog.getRadioButton();
			
			selectWindow(data_name + "_tracer.tif");
			setSlice(1);
			selectWindow("despeckled");
			setSlice(1);
		}
		
		if (chosen_threshold == "method=Drawn"||thresh_loop == "Draw the whole cell") { //If you decide to draw...
			close("thresh_choice");
			drawCell(); //run drawing function
			t = 1; //end loop
		}
		else if (thresh_loop == "Try a different threshold") {
			close("thresh_choice");
		}
		else if (thresh_loop == "Thresholding complete") {
			close("thresh_choice");
			selectWindow("despeckled");
			run("Convert to Mask", chosen_threshold+" background=Dark calculate");
			run("Set... ", "zoom=" + zoom*100);
			selectWindow("despeckled");

			rethresh = fillHoles(); //Runs fill holes and returns user's choice about going back to threshold
			//true input here ensures user is given the option to re-run threshold
			
			if (!rethresh) { //If you didn't want to re-run threshold after filling holes...
				close("threshold options");
				cell_size = sizeExclusion("Whole Cell", cell_size, "Cell");
				call("ij.Prefs.set", "blebs.cell_size", cell_size);
				separateNoise(cell_size); //...separate background noise by size exclusion and then by tracing if needed...
				t=1; //...and end loop to move to the whole cell step
			}
			else if (rethresh) { //if retrying threshold, close the options we tried and start over
				close("despeckled");
				close("thresh_choice");
				selectWindow(data_name + "_tracer.tif");
				run("Duplicate...", "title=despeckled duplicate");
				run("Set... ", "zoom=" + zoom*100);
			}
		}
	}
}

//drawCell() contains the logic needed to properly draw the cell outline on the image. involves an auto-positioning feature via orgWindows() to intuitively arrange windows.
function drawCell() {
	if(isOpen("threshold options")) {
		close("threshold options");
	}
	if(isOpen("threshold choice")) {
		close("threshold choice");
	}
	if(!isOpen("despeckled")) {
		tracerFinder();
		selectImage(tracer_id);
		run("Duplicate...", "title=despeckled duplicate");
		run("Set... ", "zoom=" + zoom*100);
	}
	setTool("freehand");
	setBackgroundColor(0, 0, 0);
	setForegroundColor(255, 255, 255);
	run("Line Width...", "line=3");
	selectWindow("despeckled");
	run("8-bit");
	orgWindows(left[0], right[0], "trace", auto_pos, false);
	
	// User Decision loop for tracing the cell. Guides user through repeated tracing of the full cell outline
	edit_opt = newArray("Draw the cell", "Time course is complete");
	i = 0;
	while (i == 0) {
		//Dialog - advance after tracing to create cell outline, or indicate if finished
		Dialog.createNonBlocking("Trace cell");
		Dialog.addMessage("Outline the cell on the despeckled image");
		Dialog.addMessage("Indicate when finished");
		Dialog.addRadioButtonGroup("", edit_opt, 2, 1, edit_opt[0]);
		if (auto_pos) Dialog.setLocation(db_x, db_y);
		Dialog.show();
		edit_choice = Dialog.getRadioButton();
	
		selectWindow("despeckled");
		if(edit_choice == edit_opt[0]&& is("area")) { //draw if the user selected the draw option and has an area selected on the image
			run("Draw", "slice"); //draws a line that expands the area you chose by a few pixels. helps because the selection line is very thin and hard to accurately use.
			run("Fill", "slice");
			run("Clear Outside", "slice"); //colors in the area you traced as white, labelling it as part of a cell.
		}
		else if(edit_choice == edit_opt[1]) { //if the user says they're done, convert to a binary image
			selectWindow("despeckled");
			run("Select None");
			setOption("BlackBackground", false);
			setAutoThreshold("Triangle dark");
			run("Convert to Mask", "method=Triangle background=Dark");
			run("Set... ", "zoom=" + zoom*100);
			chosen_threshold = "method=Drawn"; //track that the user drew the cell, for naming the threshold file
			resetThreshold;
			i = 1;
		}
		if (!zoomChecker(false) && auto_pos) { //reorg windows if desired and if the zoomchecker notices that the windows have changed zoom.
			orgWindows(left[0], right[0], "trace", auto_pos, true);
		}
		setTool("freehand");
	}
	selectWindow("despeckled");
	rename(data_name + "_threshold_" + chosen_threshold + ".tif");
	saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
}

//orgWindows() moves the dialog box (see dbLoc()) and the image windows so that they fit easily on one screen. 
function orgWindows(l_win, r_win, task, pos, redo) {
	if(!redo) {
		dbLoc(task, "");
		if(!isOpen("Synchronize Windows")) {
			run("Synchronize Windows");
		}
		waitForUser("Click 'Synchronize All' button in 'Synchronize Windows' pop-up");
		z1 = zoom;
		z2 = zoom;
	}
	if(!pos) {
		return;
	}
	selectWindow(l_win);
	if(redo) {
		getLocationAndSize(ix, iy, ih, iw);
		z1 = widthToZoom(ih / getHeight());
		dbLoc(task, z1);
	}
	else setSlice(1);
	setLocation(5, (screenHeight-getHeight()*z1)/2-50);
	selectWindow(r_win);
	if(redo) z2 = getZoom();
	else setSlice(1);
	setLocation(10 + db_w + getWidth()*z1, (screenHeight-getHeight*z2)/2 -50);
	
}

//widthToZoom() changes the (scalar) normalized size of the image window relative to the screen to a (discrete) zoom value. used in orgWindows() and zoomChecker()
function widthToZoom(sw) {
	z_set = newArray(4, 3, 2, 1.5, 1, 0.75, 0.5, (1/3), 0.25, (1/6), 0.125);
	//loop to compare input width ratio to the ImageJ standard set of discrete zoom values
	for(i = 0; i < z_set.length; i++) {
		if(z_set[i] < sw) {
			new_z = z_set[i];
			return new_z;
		}
	}
}

//zoomChecker() is used to compare the current zoom of an image to the ideal zoom of that image given the size of the screen.
//this allows the plugin to automatically adjust image zoom as needed throughout tracing steps. if zoom for an image is not
//scaled in order to fit all images on screen at once while still remaining at maximum size, the appropriate adjusted size
//is stored in memory and the function returns false, indicating change of zoom is required.
function zoomChecker(init) {
	images = getList("image.titles");
	if(init) {
		selectWindow(images[0]);
		sizes = newArray(getZoom(), getZoom());
		return;
	}
	if (isOpen("threshold options")) images = Array.deleteValue(images, "threshold options"); //catches case during fill holes when threshold options is open
	check = true;
	//loop to scan each open image and log their size in the sizes array
	for(i = 0; i < images.length; i++) {
		selectWindow(images[i]);
		getLocationAndSize(ax, ay, w, h);
		test_z = widthToZoom(w / getWidth());
		if (images[i] == "threshold options") {
			continue;
		}
		if(test_z != sizes[i]) {
			check = false;
		}
		sizes[i] = test_z;
	}
	return check;
}

//zoomFinder() looks at the scalar zoom of the image (described as sw below) and converts it to an appropriate discrete zoom size from the z_set array based on its size.
//Each zoom must be smaller than 2/3 of the display screen (zh_ub) or larger than 2/5 of the display screen (zw_ub), and must be wide enough to fit another equal size image
//and a dialog box of max size 377 pixels wide (zw_b). This function checks that all of this is true and sets the stored zoom value to the appropriate zoom.
function zoomFinder() {
	zh_lb = screenHeight/(getHeight()*2.5);
	zh_ub = screenHeight/(getHeight()*1.5);
	zw_b = (screenWidth - 377)/(getWidth()*2); // zoom width bound find zoom where largest dialog box for tracing (width of 377) can still fit between two images on screen without anything overlapping
	getLocationAndSize(ax, ay, w, h);
	sw = w / getWidth();
	z_set = newArray(4, 3, 2, 1.5, 1, 0.75, 0.5, (1/3), 0.25, (1/6), 0.125);
	
	if (sw > zh_ub) { //if the height of the image window is too large
		for(i = 0; i < z_set.length; i++) { //scan from largest to smallest discrete zoom
			if(z_set[i] < zh_ub) { //when you reach the largest zoom that is smaller than the upper height limit
				zoom = z_set[i]; //reset it
				return;
			}
		}
	}
	else if (sw > zw_b) { //if the image is too wide to fit twice on the screen with a dialog box between
		for(i = 0; i < z_set.length; i++) { //scan from largest to smallest discrete zoom
			if(z_set[i] < zw_b) { //when you reach the largest zoom that still allows two images to fit with DB between
				zoom = z_set[i];  //reset it
				return;
			}
		}
	}
	else if (sw < zh_lb) { //if the height of the image is small relative to screen size
		for(i = z_set.length - 1; i >=0 ; i--) { //scan from smallest to largest discrete zoom
			if(z_set[i] > zh_lb) { //when you reach the largest zoom that is smaller than the lower height limit
				zoom = z_set[i]; //reset it
				return;
			}
		}
	}
	else {
		zoom = getZoom();
		return;
	}
}

//fillHoles() takes user through process of removing any holes within or on the sides of the cell. Holes within are automatically filled by ImageJ's Fill Holes, while
//holes on edges must be drawn back in by user and corrected.
function fillHoles() {
	if(!isOpen("despeckled")) {
		selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
		rename("despeckled");
	}
	
	holeQ1 = newArray("Yes", "No");
	selectWindow("despeckled");
	//Dialog - Check if any holes are present
	Dialog.createNonBlocking("Fill Holes");
	Dialog.addMessage("Check all frames for holes inside the cell"); 
	Dialog.addMessage("Are there holes you need to fill?");
	Dialog.setLocation(getDbX(), (screenHeight/2-200));
	Dialog.addRadioButtonGroup("", holeQ1, 1, 2, holeQ1[0]);
	Dialog.show();
	holeQ1_ans = Dialog.getRadioButton();
	
	if 	(holeQ1_ans == "Yes") {
		selectWindow("despeckled");
		run("Fill Holes", "stack");
		
		//Re-fill holes if necessary
		selectWindow("despeckled");
		//Dialog - Check if holes remain after initial automated filling
		Dialog.createNonBlocking("Re-fill Holes"); 
		Dialog.addMessage("Re-check all frames for holes inside the cell"); 
		Dialog.addMessage("Are there still holes left?"); 
		holeQ2 = newArray("Yes", "No", "Try a different threshold");
		Dialog.addRadioButtonGroup("", holeQ2, 3, 1, holeQ2[1]);
		Dialog.setLocation(getDbX(), (screenHeight/2-200));
		Dialog.show();
		holeQ2_ans = Dialog.getRadioButton();
		
		if 	(holeQ2_ans == "Yes") {
			orgWindows(left[1], right[1], "holes", auto_pos, false);
			setForegroundColor(0, 0, 0);
			setTool("freeline");
			run("Line Width...", "line=" + line_w);
			// User Decision loop to trace over the proper outline of the cell to fill any holes
			//around the edges of the cell until indicated that they're done.
			edit_opt = newArray("Draw the cell outline", "Time course is complete");
			i = 0;
			while (i == 0) {
				//Dialog - trace to fill holes at edges as needed
				Dialog.createNonBlocking("Trace then fill holes");
				Dialog.addMessage("Trace the outline of the cell where needed. Make sure the\nline runs from black to black on the despeckled image");
				Dialog.addMessage("Indicate when finished");
				Dialog.addRadioButtonGroup("", edit_opt, 2, 1, edit_opt[0]);
				if (auto_pos) Dialog.setLocation(db_x, db_y);
				Dialog.show();
				edit_choice = Dialog.getRadioButton();
				selectWindow("despeckled");
				if(edit_choice == edit_opt[0] && is("line")) {
					selectWindow("despeckled");
					run("Draw", "slice");
					run("Fill Holes", "slice");
				}
		    	else if(edit_choice == edit_opt[1]) {
		    		i = 1;
		    		run("Select None");
		    	}
		    	setTool("freeline");
		    	if(!zoomChecker(false) && auto_pos) {
		    		orgWindows(left[1], right[1], "holes", auto_pos, true);
		    	}
			}
			selectWindow("despeckled");
			saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
			return false;
		}
		else if (holeQ2_ans == "No") {
			selectWindow("despeckled");
			rename(data_name + "_threshold_" + chosen_threshold + ".tif");
			saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
			return false;
		}
		if (holeQ2_ans == "Try a different threshold") {
			return true;
		}
	}
	else {
		selectWindow("despeckled");
		rename(data_name + "_threshold_" + chosen_threshold + ".tif");
		saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
		return false;
	}
}

//separateNoise() contains logic for separating and removing from the cell of interest any noise or other object like another cell that is attached to it. It asks the user to draw a line between the cell of interest and the noise object, and then
//creates a line separating the two. If the object is smaller than the scale of the cell (as determined by the size gate chosen by the user) then the object is automatically removed. If not, then the object remains on the image and is later removed
//by the user through a separate mechanism
function separateNoise(input_size) {
	selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
	run("Analyze Particles...", "size="+ input_size +"-Infinity show=Masks clear stack");
	close(data_name + "_threshold_" + chosen_threshold + ".tif");
	run("Set... ", "zoom=" + zoom*100);
	rename(data_name + "_threshold_" + chosen_threshold + ".tif");
	
	noise = newArray("There is noise attached to the cell", "No noise is attached to the cell");
	//Dialog - remove any objects attached to the cell
	Dialog.createNonBlocking("Attached Noise Objects");
	Dialog.addMessage("Check all frames to see if anything is touching the cell of interest\n\nThis could be background noise or another cell"); //here noise is anything large enough and attached means its touching the cell.
	Dialog.addRadioButtonGroup("", noise, 2, 1, noise[1]);
	Dialog.setLocation(getDbX(), (screenHeight/2-200));
	Dialog.show();
	noise_ans = Dialog.getRadioButton();
	
	
	if (noise_ans == "There is noise attached to the cell") {
		orgWindows(left[2], right[2], "attached", auto_pos, false);
		setForegroundColor(255, 255, 255);
		setBackgroundColor(255, 255, 255);
		setTool("freeline");
		run("Line Width...", "line=" + Math.ceil(Math.sqrt(width*height)/205));
		// User Decision Loop to draw a line that separates the cell and any noise or other object attached to it as desired.
		i = 0;
		edit_opt = newArray("Separate noise object", "Time course is complete");
		while (i == 0) {
			
			//Dialog - trace line between touching objects, and they will be separated. If a small object is created through this, it is removed.
			Dialog.createNonBlocking("Remove attached objects");
			Dialog.addMessage("Look for places where interesting cell(s)\nhave noise attached or touch each other. Then,\ntrace the cell outline on that spot on the tracer\nimage. Indicate when finished.");
			Dialog.addMessage("You will have a chance to select\nthe cell of interest in the next step.");
			Dialog.addRadioButtonGroup("", edit_opt, 2, 1, edit_opt[0]);
			if (auto_pos) Dialog.setLocation(db_x, db_y);
			Dialog.show();
			edit_choice = Dialog.getRadioButton();
			selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
			if(edit_choice == edit_opt[0] && is("line")) {
				run("Draw", "slice");
				run("Analyze Particles...", "size=0-" + input_size + " clear add slice");
				roiManager("fill");
				roiManager("reset");
				close("ROI Manager");
			}
			if(edit_choice == edit_opt[1]) {
				i = 1;
			}
			if(!zoomChecker(false) && auto_pos) {
				orgWindows(left[2], right[2], "attached", auto_pos, true);
			}
			setTool("freeline");
		}
		saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
	}
}

//multiThresh runs through the logic required to analyze multiple cells isolated on a threshold image. It is the main logic that guides the process of analyzing multiple cells on the same image, and is called multiThresh because
//all main steps of pre-processing up to the threshold step remain the same in the case of multiple cells of interest to be analyzed.
function multiThresh() {
	root_source = source; //original source for saving threshold image that is repeatedly referenced
	og_name = data_name; //data_name before adding labels or changing the original name
	og_threshold = chosen_threshold;
	//Dialog - find cells present on threshold
	Dialog.createNonBlocking("Multiple Cells on Threshold");
	Dialog.addMessage("Indicate which cells are present on the threshold");
	thresh_mult = newArray(labels.length);
	labels_cell = Array.copy(labels);
	//loop creates text to check for the presence of each cell as indicated in previous mult labelling step
	for (l = 0; l < labels_cell.length; l++) {
		labels_cell[l] = "Cell '" + labels_cell[l] + "' is present on threshold";
	}
	Array.fill(thresh_mult, false);
	Dialog.addCheckboxGroup(labels_cell.length, 1, labels_cell, thresh_mult);
	Dialog.show();
	
	//loop to record each cell indicated to be present on the threshold image
	for(l = 0; l < thresh_mult.length; l++) {
		thresh_mult[l] = Dialog.getCheckbox();
	}
	
	//loop to isolate and analyze each cell of interest while working from the original, multi-cell threshold for each indicated cell
	for (l = 0; l < thresh_mult.length; l++) {
		selectWindow(og_name + "_tracer.tif");
		rename(batch_names[l] + "_tracer.tif");
		selectWindow(og_name + "_threshold_" + chosen_threshold + ".tif");
		rename(batch_names[l] + "_threshold_" + chosen_threshold + ".tif");
		source = batch_sources[l];
		data_name = batch_names[l];
		setMeasures();
		if(thresh_mult[l]) {
			//Dialog - isolate cell of interest by clocking on it
			Dialog.createNonBlocking("Choose Cell " + labels[l]);
			Dialog.addMessage("In the following steps, click on cell " + labels[l] + "\non the threshold image to isolate it");
			Dialog.addCheckbox("Choose a different frame range", false);
			Dialog.show();
			
			if(Dialog.getCheckbox()) {
				selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
				sliceKeeper(true, "cell"); //run sliceKeeper with mult input to true, so that it changes range for tracer and threshold images
				selectWindow(data_name + "_tracer.tif");
				saveAs("tiff", source + data_name + "_tracer.tif");
				selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
				setMeasures();
			}
			threshPick(cell_size, "cell", data_name + "_threshold_" + chosen_threshold + ".tif");
			saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
		}
		else {
			//Dialog - choose method to edit threshold for non-present cells
			Dialog.createNonBlocking("Isolating Cell " + labels[l]);
			m_thresh_redo = newArray("Draw the cell", "Try a different threshold");
			Dialog.addRadioButtonGroup("", m_thresh_redo, 2, 1, m_thresh_redo[0]);
			Dialog.addCheckbox("Choose a different frame range", false);
			Dialog.show();
			
			range = Dialog.getCheckbox();
			m_thresh_rechoice = Dialog.getRadioButton();
			close(data_name + "_threshold_" + chosen_threshold + ".tif");
			selectWindow(data_name + "_tracer.tif");
			saveAs("tiff", source + data_name + "_tracer.tif");
			setMeasures();
			
			if(range) {
				selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
				sliceKeeper(true, "cell");
				selectWindow(data_name + "_tracer.tif");
				saveAs("tiff", source + data_name + "_tracer.tif");
				selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
			}
			
			//Draw the cell if the user doesn't want to rethreshold the original image set to capture it
			if(m_thresh_rechoice == m_thresh_redo[0]) {
				drawCell();
			}
			//Run a different threshold with re-cleaning if the image isn't present
			else if(m_thresh_rechoice == m_thresh_redo[1]) {
				threshOptions();
			}
		}
		setMeasures();
		
		//reset the sub_name so that it remains a length of 31 characters, while still adding the label at the end.
		sub_name = data_name;
		if (lengthOf(data_name) >= 31) {
			sub_name = substring(data_name, lengthOf(data_name) - 30);
		}
		//run logic for partitioning cell to isolate cell body from blebs
		cellPartition(true);
		close("*");
		waitForUser("Analysis of cell " + labels[l] + " is complete!");
		
		//Open the original tracer and threshold files
		open(root_source + File.separator + og_name + "_tracer.tif");
		run("Set... ", "zoom=" + zoom*100);
		resetMinAndMax;
		run("Enhance Contrast", "saturated=0.35");
		open(root_source + File.separator + og_name + "_threshold_" + og_threshold + ".tif");
		run("Set... ", "zoom=" + zoom*100);
	}
}

//threshCheck runs a check on the threshold image to confirm that each frame has one image on it. This is used in places in the plugin as a prerequisite for triggering a method that prompts the user to isolate the cell of interest from other
//large objects present on the cell.
function threshCheck() {
	selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
	run("Analyze Particles...", "size=" + cell_size + "-Infinity clear stack");
	return (getValue("results.count") == nSlices);
}

//threshPick scans through each frame in an image and isolates one object on that frame of the user's choosing.
//It is used during the individual bleb analysis function, blebTracker, after threshold cleaning if threshCheck indicates multiple objects
//are present in the frame, and in the multiThresh function used for multi-cell analysis to isolate the cell of interest from a cleaned threshold image.
function threshPick(input_size, type, window) {
	if(isOpen("Synchronize Windows")) {
		waitForUser("Click *UN*synchronize all in Synchronize Windows");
	}
	setForegroundColor(255, 255, 255);
	setBackgroundColor(255, 255, 255);
	selectWindow(window);
	//Loop scans through every slice and stops wherever there is more than one object on the slice, requiring user to click on the one desired for analysis.
	for(f=1; f <= nSlices; f++) {
		setSlice(f);
		num_large_objs = 0;
		setAutoThreshold("Triangle light");
		run("Analyze Particles...", "size=" + input_size + "-Infinity clear add slice");
		count = roiManager("count");
		if(count > 1) {
			run("Labels...", "color=blue font=" + (width/32) + " show");
			// User Decision loop waits for selection of the object of interest on the threshold. Ensures that the user selected an actual object before trying to remove everything else on image.
			k = 0;
			while (k == 0) {
				waitForUser("Click on the blue number corresponding to the " + type + " of interest\nWhen the " + type + " is outlined in blue, click okay");
				if(is("area")) {
					k = 1;
				}
			}
			run("Clear Outside", "slice");
			run("Select None");
		}
		roiManager("reset");
		close("ROI Manager");
		resetThreshold;
	}
}

//// blebTracker contains logic for gathering data about a bleb's lifetime. Requires user to indicate the range of frames in which the bleb is present
//// and click on a bleb of interest on each frame. When complete, it will return data on bleb lifetime
function blebTracker() {
	first_slice = 1;
	last_slice = nSlices;
	i = 1;

	// User Decision Loop to repeat the process of tracking a bleb as desired.
	while(true) {

		selectWindow(data_name + "_all_blebs.tif");
		
		//Dialog - provide parameters for tracking bleb, including frame range
		Dialog.createNonBlocking("Bleb Tracking");
		Dialog.addMessage("Set bleb frame range, frame rate, time unit, and size.");
		Dialog.addNumber("Range for bleb #", i);
		Dialog.addNumber("First Frame: ", first_slice, 0, 3, "");  
		Dialog.addNumber("Last Frame: ", last_slice, 0, 3, "");
		Dialog.addCheckbox("Bleb tracking is finished", false);
		Dialog.show();

		if (Dialog.getCheckbox()) {
			break;
		}
		bleb_num = Dialog.getNumber();
		first_slice = Dialog.getNumber();;
		last_slice = Dialog.getNumber();;;

		selectWindow(data_name + "_all_blebs.tif");
		run("Slice Keeper", "first=" + first_slice +" last=" + last_slice + " increment=1");
		rename(data_name + "_bleb_" + i + ".tif");
		close(data_name + "_all_blebs.tif");
		threshPick(bleb_size, "bleb", data_name + "_bleb_" + i + ".tif");
		run("Select None");
		run("Analyze Particles...", "size=1 show=Nothing display clear stack");
		run("Set... ", "zoom=" + zoom*100);
		rename(data_name + "_bleb_" + i + ".tif");
		saveAs("tiff", source + data_name + "_bleb_" + i + ".tif");
		//loop to add time measure for each row of data, by referencing slice number in case of frames with no objects
		for (row=0; row<nResults; row++) {
			time = rate * (getResult("Slice", row)-1);
    		setResult(rate_unit, row, time);
		}
		updateResults();
		selectWindow("Results");
		rename(data_name + "_bleb_" + i + "_results.csv");
		saveAs("results", source + data_name + "_bleb_" + i + "_results.csv");
		close(data_name + "_bleb_" + i + ".tif");
		selectWindow(data_name + "_bleb_" + i + "_results.csv");
		run("Close");
		open(source + data_name + "_all_blebs.tif");
		
		i++;
	}
}
//// dbLoc() changes the stored value for the screen height location (db_y) and the width (db_w) of the dialog boxes used during any plugin steps with drawing involved.
//// This is to allow the windows to be properly oriented on screen so that they don't overlap. All numbers were measured based on a 1920 x 1080 resolution screen, and were tested
//// across several monitors of different sizes and found to be appropriate.
function dbLoc(task, z_inp) {
	if (isNaN(z_inp)) db_x = 20 + zoom*getWidth();
	else db_x = 20 + z_inp*getWidth();
	db_y = screenHeight/2;
	
	if(task == "attached") {
		db_y -= 130;
		db_w = 306;
	}
	else if (task == "cell body") {
		db_y -= 109;
		db_w = 312;
	}
	else if (task == "holes") {
		db_y -= 122;
		db_w = 377;
	}
	else if (task == "trace") {
		db_y -= 109;
		db_w = 292;
	}
	else {
		print("dbloc error");
	}
}

//// lineWidth calculates the proper width of the line used for steps like manually filling holes, removing noise, and tracing the cell body
//// based on the dimensions of the given image.
function lineWidth() {
	line_w = Math.ceil(Math.sqrt(width*height)/205);
	if (line_w < 3) {
		line_w = 3;
	}
}

//// findSpeed calculates the speed of an object. it's written to only calculate the speed of the cell body so as to properly track cell movemement while excluding bleb movement.
function findSpeed() {
	if(isNaN(getResult('X', 1))||isNaN(getResult('Slice', 1))) {
		if(isNaN(getResult('X', 1))) measures = measures + " centroid";
		if(isNaN(getResult('Slice', 1))) measures = measures + " stack";
		run("Set Measurements...", measures);
		run("Analyze Particles...", "size=" + cb_size + "-Infinity show=Nothing display clear stack");
	}
	//loop adds time, distance, and speed values for each row. time is calculated in reference to slice number in case of empty frames
	for (row=1; row<nResults; row++) {
		time = rate * (getResult("Slice", row)-1);
		x_path = getResult('X', row) - getResult('X', row-1);
		y_path = getResult('Y', row) - getResult('Y', row-1);
		cell_path = sqrt(Math.sqr(x_path) + Math.sqr(y_path));
		inst_speed = cell_path / rate;
		setResult(rate_unit, row, time);
		setResult("Distance", row, cell_path);
		setResult("InstSpeed", row, inst_speed);
	}
	updateResults();
}

//// collectAreas() records the area values of subcellular components on a per frame basis in an area_comp.csv file. It references the type input to properly label the area
//// based on the subcellular component type, and in analyzing the all_blebs image, also includes a measure of the number of blebs present on each frame of the image.
function collectAreas(type) { 
	return_no_batch = false;
	if(!is("Batch Mode")) {
		setBatchMode(true);
		return_no_batch = true;
	}
	if(isNaN(getResult("Area", 1))) return;
	selectWindow("Results");
	result_slices = Table.getColumn("Slice");
	if(!File.exists(source + data_name + "_area_comp.csv")) { //If the area comparison table doesn't exist, create it and add Slices column
		Table.create(data_name + "_area_comp.csv");
		table_slices = newArray(nSlices);
		//Loop to populate an array corresponding to each slice in an image
		for (i = 0; i < nSlices; i++) {
			table_slices[i] = i+1;
		}
		Table.setColumn("Slice", table_slices);
	}
	else Table.open(source + data_name + "_area_comp.csv");
	if(isNaN(getResult('Slice', 1))) {
		measures = measures + " stack";
		run("Set Measurements...", measures);
		run("Analyze Particles...", "size=10-Infinity show=Nothing display clear stack");
	}
	areas = newArray(nSlices);
	if(type == "all_blebs") {
		slice_area = 0;
		slice_blebs = 0;
		num_blebs = newArray(nSlices);
		row = 0; 
		slice = 1; 
		while(row < nResults && slice <= nSlices) { //for each row in results
			if(getResult('Slice', row) != slice - 1) { //if a frame was skipped (i.e. the slice number of the current row is not one more than the previous row's slice number)
				slice = getResult('Slice', row); //reset the slice number
			}
			
			//Find the area for the first bleb from the current slice in the results table
			slice_area += getResult('Area', row); //get the area of the current row
			slice_blebs++; //one bleb was tracked
			row++; //move to the next row
			
			//Add area for other blebs from the same image to the summary area value for this slice
			if(row < nResults) { //if we're not on the last row
				while(getResult('Slice', row) == getResult('Slice', row-1)) { //if the next row has data from the same slice
					slice_area += getResult('Area', row); //add that area to the slice_area
					slice_blebs++; //add bleb to total
					if (row+1 < result_slices.length) row++; //if we're not at the last row, move forward
					else break; //if we are on the last row, we're done
				}
			}
			areas[slice-1] = slice_area; //set slice area in array
			num_blebs[slice-1] = slice_blebs; //set number of blebs on frame in array
			slice++; //move to next slice
			slice_area = 0; //reset slice_area tracker
			slice_blebs = 0; //reset slice_bleb tracker
		}
		Table.setColumn(type + " Area", areas);
		Table.setColumn("NumBlebs", num_blebs);
	}
	else {
		row = 0;
		while(row < result_slices.length) {
			areas[result_slices[row]-1] = getResult('Area', row); //get the slice for that row, then set that slice's area in the areas array
			//this is necessary instead of simply grabbing the area for each row and adding it to the areas array at areas[row] because some slices may not have an area, and we want an "area per slice" measure
			row++;
		}
		Table.setColumn(type + " Area", areas);
	}
	Table.save(source + data_name + "_area_comp.csv");
	selectWindow(data_name + "_area_comp.csv");
	run("Close");
	if(return_no_batch) {
		setBatchMode(false);
	}
}

//// linearSearch() is a simple linear search method for finding the index of an item in an array without sorting. The function returns the index of the first partial match for the 
//// term in the input array (arr). It is implemented to find the row index of the summary stats table in the summary_stats function. We want to find the first instance of a partial
//// match because the term will always be a type input from collectSummaryStats(), so we're looking for the first instance of a measurement from the section of the plugin that is 
//// being written by collectSummaryStats(). A binary search would perform better here, but we don't want to sort the input  array, which is already sorted in row order. This way,
//// the index returned by linearSearch() will match the appropriate row index for reference when deleting unwanted values.
function linearSearch(term, arr) {
	scan = 0; //scan is item in array being checked, starting from first (looking for first instance)
	while(scan < arr.length){
		if(arr[scan].contains(term)) { //if we get a match or partial match
			return scan; //return the corresponding index
		}
		scan++;
	}
	return -1; //if we didn't find it, return a nonsense index.
}


//// collectSummaryStats() writes summary data for relevant measurement statistics to a summary_stats.csv file to reference mean, minimum, maximum, standard deviation, and N
//// for each measure on a per-frame basis. This includes plugin-created speed measures. It takes the type input, which is a string indicating which subcellular component each 
//// measurement corresponds to (e.g. whole_cell Area v. all_blebs Area). Area comparison measures are added to this summary file in the compareAreas step.
function collectSummaryStats(type) { 
	return_no_batch = false;
	if(!is("Batch Mode")) {
		setBatchMode(true);
		return_no_batch = true;
	}
	if(!File.exists(source + data_name + "_summary_stats.csv")) { //If the area comparison table doesn't exist, create it and add Slices column
		Table.create(data_name + "_summary_stats.csv");
		row = 0;
	}
	else  { //check if this plugin file's summary data was collected previously
		Table.open(source + data_name + "_summary_stats.csv");
		selectWindow(data_name + "_summary_stats.csv");
		row_labels = Table.getColumn("name");
		row_labels_str = String.join(row_labels); //string used below to avoid searching if type is not present
		if(row_labels_str.contains(type)) { //check if data from this section of the plugin onward has previously been collected
			first_instance = linearSearch(type, row_labels); //find index of first instance of type in a row label
			Table.deleteRows(first_instance, Table.size-1); //delete everything from that row down to allow for replacement
		}
		row = Table.size;
	}
	
	//Summary statistics not applied to measures in the exclusions array
	//These measures either provide non-relevant summarys (e.g. positional data from X Y centroid) or can return NaN values (Skew, Kurt)
	exclusions = newArray("X", "Y", "XM", "YM", "BX", "BY", "Angle", "Skew", "Kurt", "Slice", "FeretX", "FeretY", "FeretAngle", "Minutes", "Seconds"); 
	headings = split(String.getResultsHeadings);
	//loop to remove any excluded outputs that are present in the data collected by the user
	for(i = 0; i < exclusions.length; i++) {
		headings = Array.deleteValue(headings, exclusions[i]);
	}
	
	//loop to pull data for a measure into an array (curr_measure) depending on the naming scheme established in collectAreas()
	//then to calculate and write values for summary statistic measures in the summary_stats table
	for(i = 0; i < headings.length; i++) {
		selectWindow("Results");
		curr_measure = Table.getColumn(headings[i]);
		if (headings[i] == "InstSpeed" || headings[i] == "Distance" || headings[i] == "NumBlebs") {
			row_name = headings[i];
		}
		else row_name = type + " " + headings[i];
		if (headings[i] == "InstSpeed" || headings[i] == "Distance") {
			curr_measure = Array.deleteIndex(curr_measure, 0); //in case of distance and speed, first value is always 0 as a placeholder, so remove it from stats
		}
		len = curr_measure.length; 
		selectWindow(data_name + "_summary_stats.csv");
		Array.getStatistics(curr_measure, min, max, mean, stdDev);
		stats = newArray(mean, max, min, stdDev, len);
		Table.set("name", row, row_name);
		Table.set("mean", row, stats[0]);
		Table.set("max", row, stats[1]);
		Table.set("min", row, stats[2]);
		Table.set("stdDev", row, stats[3]);
		Table.set("n", row, stats[4]);
		row++;
	}
	Table.save(source + data_name + "_summary_stats.csv");
	selectWindow(data_name + "_summary_stats.csv");
	run("Close");
	if(return_no_batch) {
		setBatchMode(false);
	}
}

//// compareAreas() uses area data for each cellular component collected in collectAreas() to produce frame-by-frame normalized area data. normalization is based on the
//// model employed in the publication associated with Analyze_Blebs.
function compareAreas() {
	//Open area comparison file and pull data from it
	Table.open(source + data_name + "_area_comp.csv");
	whole_cell_areas = Table.getColumn("whole_cell Area");
	all_blebs_areas = Table.getColumn("all_blebs Area");
	cell_body_areas = Table.getColumn("cell_body Area");
	if (leader_bleb) largest_bleb_areas = Table.getColumn("largest_bleb Area");
	
	
	//Initialize arrays as needed for area collection
	norm_bleb_size = newArray(all_blebs_areas.length); 
	norm_cb_size = newArray(cell_body_areas.length);
	if (leader_bleb) norm_largest_bleb_size = newArray(largest_bleb_areas.length);
	
	//loop to populate normalized arrays according to appropriate logic
	for(i = 0; i < all_blebs_areas.length; i++) {
		norm_bleb_size[i] = all_blebs_areas[i]/cell_body_areas[i]; //normalized bleb size = bleb area per slice / cell body area per slice
		norm_cb_size[i] = cell_body_areas[i]/whole_cell_areas[i]; //normalized cell body size = cell body area per slice / whole cell area per slice
		if(leader_bleb) norm_largest_bleb_size[i] = largest_bleb_areas[i]/cell_body_areas[i]; //normalized largest bleb size = largest bleb area per slice / cell body area per slice
	}
	
	//Add columns to the table
	Table.setColumn("NormBlebSize", norm_bleb_size);
	Table.setColumn("NormCellBodySize", norm_cb_size);
	if (leader_bleb) Table.setColumn("NormLargestBlebSize", norm_largest_bleb_size);
	Table.save(source + data_name + "_area_comp.csv");
	selectWindow(data_name + "_area_comp.csv");
	run("Close");
	
	//Add Summary Stats of normalized comparisons to summary_stats.csv
	Table.open(source + data_name + "_summary_stats.csv");
	row = Table.size;
	Array.getStatistics(norm_bleb_size, min, max, mean, stdDev);
	norm_bleb_stats = newArray(mean, max, min, stdDev, norm_bleb_size.length);
	Table.set("name", row, "NormBlebSize");
	Table.set("mean", row, norm_bleb_stats[0]);
	Table.set("max", row, norm_bleb_stats[1]);
	Table.set("min", row, norm_bleb_stats[2]);
	Table.set("stdDev", row, norm_bleb_stats[3]);
	Table.set("n", row, norm_bleb_stats[4]);
	row++;
	Array.getStatistics(norm_cb_size, min, max, mean, stdDev);
	norm_cb_stats = newArray(mean, max, min, stdDev, norm_cb_size.length);
	Table.set("name", row, "NormCellBodySize");
	Table.set("mean", row, norm_cb_stats[0]);
	Table.set("max", row, norm_cb_stats[1]);
	Table.set("min", row, norm_cb_stats[2]);
	Table.set("stdDev", row, norm_cb_stats[3]);
	Table.set("n", row, norm_cb_stats[4]);
	row++;
	if (leader_bleb) {
		Array.getStatistics(norm_largest_bleb_size, min, max, mean, stdDev);
		norm_largest_bleb_stats = newArray(mean, max, min, stdDev, norm_largest_bleb_size.length);
		Table.set("name", row, "NormLargestBlebSize");
		Table.set("mean", row, norm_largest_bleb_stats[0]);
		Table.set("max", row, norm_largest_bleb_stats[1]);
		Table.set("min", row, norm_largest_bleb_stats[2]);
		Table.set("stdDev", row, norm_largest_bleb_stats[3]);
		Table.set("n", row, norm_largest_bleb_stats[4]);
	}
	Table.save(source + data_name + "_summary_stats.csv");
	selectWindow(data_name + "_summary_stats.csv");
	run("Close");
}


//// rawToThresh contains logic for editting a raw image into a tracer version that has been cleaned up to remove any pertinent pieces of noise
//// and also calls threshold isolation and cleaning-related functions. The function ends after isolating a threshold image. This function is 
//// structured to behave appropriately for analyzing from a raw data file or from macro output files like tracer or threshold files.
function rawToThresh(mult) {

	if(skip_count > 1) { //We want to make sure the tracer is open if we're working with plugin output files
		tracerFinder();
		
	}
	
	if(skip_count == 0||((indexOf(rest_of_name, "_tracer") >=0)&&mult)) {
		//Dialog - Eliminate frames where the cell has left
		Dialog.createNonBlocking("Editing Original Image");
		Dialog.addMessage("Check to see if the cell dies/leaves the frame and for large unwanted objects");
		Dialog.addCheckbox("The frame range needs to be altered", false);
		Dialog.addCheckbox("There are large, bright, unwanted objects in frame (e.g. dead cells)", false) //large means comparable to the size of the cell. this does NOT include other cells that appear in frame at some point
		Dialog.show();
		scan_range = Dialog.getCheckbox();
		scan_junkcells = Dialog.getCheckbox();;
		
		if (scan_range == true) {
			sliceKeeper(false, "cell");
		}
		
		if (scan_junkcells == true) {
			setTool("dropper"); //this tool stores color information that is called up when drawing or erasing on the image
			waitForUser("Hold the alt key and click on a spot that is representative of background signal levels"); //sets drawing color to match background so it is excluded on threshold
			//User Decision Loop that allows user to remove large bright objects as many times as is needed.
			i = 0;
			while (i == 0) {
				setTool("freehand");
				RLO = newArray("Remove Object", "Reset Background Color", "Time course is complete");
				//Dialog - draw a circle around each bright unwanted object (dead cell, etc)
				Dialog.createNonBlocking("Remove Large Bright Objects");
				Dialog.addMessage("On each frame with a large and bright unwanted object, circle it and press the delete key\nObjects to exclude at this step would be anything brighter than the cell of interest (e.g. dead cells)");
				Dialog.addMessage("Complete the time course and indicate when finished\nChange the background color to account for photobleaching as needed");
				Dialog.addRadioButtonGroup("", RLO, 3, 1, RLO[0]);
				Dialog.show();
				RLO_choice = Dialog.getRadioButton();
				
				if(RLO_choice == RLO[0] && is("area") ) {
					run("Clear", "slice"); //color in the area with color chosen as background
				}
				else if(RLO_choice == RLO[1]) {
					setTool("dropper");
					waitForUser("Hold the alt key and click on a spot that is representative of background signal levels");
				}
				else if(RLO_choice == RLO[2]) {
					run("Select None");
					i = 1;
				}
			}
		}	
		
		//De-speckling
		run("Despeckle", "stack"); //remove noise 
		rename("despeckled");
	
		//Create a second copy of the original stack for reference in tracing
		run("Duplicate...", "title=" + data_name + "_tracer.tif duplicate");
		saveAs("tiff", source + data_name + "_tracer.tif");
		run("Set... ", "zoom=" + zoom*100);
		if(mult) {
			skip_count--;
		}
	}
	else {
		if(skip_count == 1) {
			run("Duplicate...", "title=despeckled duplicate");//creates the version of the original image that has your edits so far while you move forward
			run("Set... ", "zoom=" + zoom*100);
		}
		skip_count--;
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	//////////////////////////// YOU START FROM HERE IF YOU START FROM TRACER //////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	//Set measurements
	setMeasures();
	
	////////////////////
	//  Thresholding  //
	////////////////////
	
	if(skip_count == 0) { 
		threshOptions();
		if (!mult && !threshCheck()) {
			threshPick(cell_size, "cell", data_name + "_threshold_" + chosen_threshold + ".tif");
		}
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	//////////////////////////// YOU START FROM HERE IF YOU START FROM THRESHOLD ///////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	if (skip_count == 1) { //If the input file is a threshold file...
		
		rethresh = fillHoles(); //...run the fill holes routine without an option to re-run the threshold...
		if(rethresh) {
			close(data_name + "_threshold_" + chosen_threshold + ".tif");
			selectWindow(data_name + "_tracer.tif");
			threshOptions();
		}
		cell_size = sizeExclusion("Whole Cell", cell_size, "Cell");
		call("ij.Prefs.set", "blebs.cell_size", cell_size);
		separateNoise(cell_size);
		if(!mult && !threshCheck()) {
			threshPick(cell_size, "cell", data_name + "_threshold_" + chosen_threshold + ".tif");//...then check to remove background noise.
		}
		skip_count--; 
	}
}


//// cellPartition() conducts uses a cleaned thresholded image to conduct whole-cell analysis, guide the user through cell body isolation,
//// and conduct cell body, all blebs, and largest bleb analyses. 
function cellPartition(mult) {

	if (skip_count == 0) {
		if(invert_check) {
			invertChecker(data_name + "_threshold_" + chosen_threshold + ".tif");
		}
		
		///WHOLE CELL///
		selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
		run("Select None");
		run("Analyze Particles...", "show=Nothing display clear stack");
		run("Set... ", "zoom=" + zoom*100);
		rename(data_name + "_whole_cell"); //the edited threshold image with the isolated cell is saved as a whole cell image.
		saveAs("tiff", source + data_name + "_whole_cell.tif");
		whole_cell_loc = getInfo("image.directory");
		run("Set... ", "zoom=" + zoom*100);
		collectAreas("whole_cell");
		collectSummaryStats("whole_cell");
		run("Read and Write Excel", "file=[" + source + data_name + "_excel.xlsx] sheet=whole_cell dataset_label=whole_cell");
		//an excel sheet is created containing the whole cell data
		if (choose_xls) {
			run("Read and Write Excel", "file=[" + expt_excel + "] sheet=" + sub_name + " dataset_label=" + data_name + "_whole_cell");
			//whole cell data is added to the experimental file if desired
		}
		Table.rename("Results", data_name + "_whole_cell_results");
		saveAs("results", source + data_name + "_whole_cell_results.csv"); //data also saved as a raw csv file
		run("Close");
			
	}
	
	if(skip_count > 1) { //If you started from all_blebs or whole_cell...
		if(skip_count == 2) {
			selectWindow(data_name + "_whole_cell.tif");
			whole_cell_loc = getInfo("image.directory");
		}
		skip_count = skip_count - 2; //...skip past binarization and threshold cleaning
	}
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////// YOU START FROM HERE IF YOU START FROM WHOLE CELL /////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	
	/////////////////////
	//  Bleb analysis  //
	/////////////////////
	if (skip_count == 0) {
		selectWindow(data_name + "_whole_cell.tif");
		run("Duplicate...", "title=cell_mask duplicate");
		close(data_name + "_whole_cell.tif");
		selectWindow("cell_mask");
		run("Invert","stack");
		run("Set... ", "zoom=" + zoom*100);
		run("Line Width...", "line=3"); //allows the plugin to later draw a line in black before removing the cell body, which helps for separating blebs
		//from each other. This addition does not significantly effect data output when compared to hand-drawn analysis.
		setTool("freehand");
		setBackgroundColor(0, 0, 0);
		setForegroundColor(0, 0, 0);
		orgWindows(left[3], right[3], "cell body", auto_pos, false);
		
		//Find the cell body
		//User Decision loop for removal of cell body as many times as needed through the full time lapse
		i = 0;
		edit_opt = newArray("Remove the cell body", "Time course is complete");
		selectWindow(data_name + "_tracer.tif");
		while (i == 0) {
			//Dialog - remove cell body. Should show up between two images
			Dialog.createNonBlocking("Remove cell body");
			Dialog.addMessage("Circle the cell body so that it can be removed");
			Dialog.addMessage("Indicate when finished");
			Dialog.addRadioButtonGroup("", edit_opt, 2, 1, edit_opt[0]);
			if (auto_pos) Dialog.setLocation(db_x, db_y);
			Dialog.show(); //user circles the cell body in this step. It will be removed from the image to isolate the blebs. User can edit the same
			//frame as many times as is necessary. Anything circled before selecting "Circle cell body" will be removed.
			edit_choice = Dialog.getRadioButton();
			selectWindow("cell_mask");
			
			if(edit_choice == "Remove the cell body" && is("area")) {
				run("Draw", "slice"); //draws a thin line around the outline you made. This can prevent errors where the outline doesn't properly separate
				//blebs from each other or from the cell body
				run("Clear", "slice");
				run("Next Slice [>]");
			}
			if(edit_choice == edit_opt[1]) {
				run("Select None");
			    i = 1;
			}
			if (!zoomChecker(false) && auto_pos) {
				orgWindows(left[3], right[3], "cell body", auto_pos, true);
			}
			setTool("freehand");
		}
		
		//Bleb area, cell body area and position
		setAutoThreshold("Triangle dark");
		setOption("BlackBackground", false);
		run("Convert to Mask", "method=Triangle background=Dark calculate");
		
		bleb_size = sizeExclusion("Bleb", bleb_size, "Bleb");

		call("ij.Prefs.set", "blebs.bleb_size", bleb_size);
		
		//Find the total bleb area
		setBatchMode(true);
		open(whole_cell_loc + File.separator + data_name + "_whole_cell.tif");
		selectWindow("cell_mask");
		run("Analyze Particles...", "size=" + bleb_size + "-Infinity show=Masks stack");
		run("Analyze Particles...", "show=Overlay display clear stack"); //adds an overlay to the image for each bleb that was included as a bleb.
		collectAreas("all_blebs");
		collectSummaryStats("all_blebs");
		//Any non-included blebs will have no overlay.
		run("Labels...", "color=red font=" + (width/32) + " show"); //Each bleb gets labelled with a large red number in order of appearance
		rename(data_name + "_all_blebs");
		saveAs("tiff", source + data_name + "_all_blebs.tif"); //an all blebs image is saved
		run("Read and Write Excel", "file=[" + source + data_name + "_excel.xlsx] sheet=all_blebs dataset_label=all_blebs"); //an excel file version
		//of the all_blebs data sheet is saved
		if (choose_xls) {
			run("Read and Write Excel", "file=[" + expt_excel + "] sheet=" + sub_name + " dataset_label=" + data_name + "_all_blebs");
		}
		Table.rename("Results", data_name + "_all_blebs_results");
		saveAs("results", source + data_name + "_all_blebs_results.csv");
		run("Close"); //the results table is saved for all blebs. Each number on this sheet corresponds to the bleb number, not the slice number.
		//refer to the slice data column to match a bleb to its frame number.
	}
	
	else { //This clause applies if starting from a whole cell image and running cell body, largest bleb, or inidividual bleb analyses
		whole_check = false;
		all_check = false;
		n = 0;
		//Loop to check for whole_cell and all_blebs images. Will repeat until they are detected.
		while(n == 0) {
			images = getList("image.titles");
			
			//loop scans images and registers if any are whole_cell or all_blebs images
			for(i = 0; i<images.length; i++) {
				if(images[i] == data_name + "_whole_cell.tif") {
					whole_check = true;
					whole_loc = getInfo("image.directory");
				}
				else if(images[i] == data_name + "_all_blebs.tif") {
					all_check = true;
				}
			}
			
			if(whole_check && all_check) {
				n = 1;
			}
			else {
				if(mult) {
					open(whole_loc);
				}
				else if (!whole_check) {
					//Dialog - user finds missing whole cell image to open
					Dialog.createNonBlocking("Missing Whole Cell Image");
					Dialog.addMessage("Open the whole_cell image to create the cell body and largest bleb images");
					Dialog.addFile("Whole Cell Image: ", source);
					Dialog.show();
					whole_loc = Dialog.getString();
					open(whole_loc);
					rename(data_name + "_whole_cell.tif");
					saveAs("tiff", source + data_name + "_whole_cell.tif");
				}
				else if (!all_check) {
					//Dialog - user finds missing blebs image to open
					Dialog.createNonBlocking("Missing Blebs Image");
					Dialog.addMessage("Open the all_blebs image to create the cell body and largest bleb images");
					Dialog.addFile("Blebs Image: ", source);
					Dialog.show();
	
					open(Dialog.getString());
					rename(data_name + "_all_blebs.tif");
					saveAs("tiff", source + data_name + "_all_blebs.tif");
				}
			}
		}
		
		setBatchMode(true);
		skip_count--;
	}
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	///////////////////////// YOU START FROM HERE IF YOU START FROM ALL BLEBS //////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	if (skip_count == 0) {
		
		//Run individual bleb analysis before conducting cell body and largest bleb analyses
		if(indiv_bleb) {
			setBatchMode(false);
			selectWindow(data_name + "_all_blebs.tif");
			run("Set... ", "zoom=" + zoom*100);
			blebTracker(); //runs individual bleb function
			selectWindow(data_name + "_tracer.tif");
			close("\\Others");
			setBatchMode(true);
			open(source + File.separator + data_name + "_whole_cell.tif");
			open(source + File.separator + data_name + "_all_blebs.tif");
			
		}
		
		//Find the cell body area and position
		imageCalculator("Subtract create stack", data_name + "_whole_cell.tif", data_name + "_all_blebs.tif"); //the blebs (as isolated in the all blebs
		//image) are removed from the mask of the whole cell taken before bleb processing. The resulting image has just the cell body.
		rename(data_name + "_cell_body");
		if (cb_size == "") cb_size = 0.25*cell_size;
		run("Analyze Particles...", "size=" + cb_size + "-Infinity display clear stack"); //This runs the analysis for the whole cell and ensures that the whole cell
		//is isolated. The size is set to 50 because it is larger than the minimum bleb size but much smaller than the whole cell size. This should
		//capture all varieties of cell body sizes while excluding invisible background.
		findSpeed();
		collectAreas("cell_body");
		collectSummaryStats("cell_body");
		run("Read and Write Excel", "file=[" + source + data_name + "_excel.xlsx] sheet=cell_body dataset_label=cell_body");
		if (choose_xls) {
			run("Read and Write Excel", "file=[" + expt_excel + "] sheet=" + sub_name + " dataset_label=" + data_name + "_cell_body");
			//saved to experimental file if desired
		}
		
		Table.rename("Results", data_name + "_cell_body_results");
		saveAs("results", source + data_name + "_cell_body_results.csv"); //data is saved as an excel file and as a csv results file for the cell_body file.
		run("Close");
		selectWindow(data_name + "_cell_body");
		saveAs("tiff", source + data_name + "_cell_body.tif");
		close();
		selectWindow(data_name + "_whole_cell.tif");
		close();
		
		//scan for cell_mask image and close if not already closed. this step is needed in some multi cell cases.
		images = getList("image.titles");
		mask_check = false;
		//loop to check if the cell_mask image is still open, and then to close it if so
		for(i = 0; i < images.length; i++) {
			if(images[i] == "cell_mask") {
				mask_check = true;
			}
		}
		if(mask_check == true) {
			selectWindow("cell_mask");
			close();
		}
		
		selectWindow(data_name + "_all_blebs.tif");
	}
	
	
	if (leader_bleb) {
		/////////////////////////////
		//  Largest Bleb Analysis  //
		/////////////////////////////

		run("Set... ", "zoom=" + zoom*100);
		setSlice(1);
		
		//Isolate the largest bleb if desired
		
		run("Remove Overlay"); //removes the overlay that indicated bleb numbers
		run("Invert", "stack");
		
		//This section of the plugin is based on a plugin by G. Landini at the following citation:
		//Landini G. Advanced shape analysis with ImageJ. Proceedings of the Second ImageJ User and Developer Conference, Luxembourg, 
		//6-7 November, 2008. p116-121. ISBN 2-919941-06-2. Plugins available from https://blog.bham.ac.uk/intellimic/g-landini-software/
		
		setThreshold(0, 127);
		n = 0;
		//Loop to repeatedly isolate largest bleb on each frame
		while (n<=nSlices-1){
			run("Analyze Particles...", "size=" + bleb_size + "-Infinity show=Nothing clear record");
			area=0;
			//loop to locate largest area
		    for (i=0; i<nResults; i++) {
		       count = getResult('Area', i);
		       if (count>area) area=count; //scanning through the results, whichever bleb in each frame has the highest area on each frame has its
		       // area value saved in the "area" variable
		     }
		    //loop to remove every bleb on each frame except for the largest
		    for (i=0; i<nResults; i++) {
		       x = getResult('XStart', i); //find the x...
		       y = getResult('YStart', i); //...and the y...
		       count = getResult('Area', i); //...for every bleb in each frame
		       if (count<area) { //if the area of the bleb on the list is less than the max area...
		           doWand(x,y); //...circle that smaller bleb...
		           setBackgroundColor(0, 0, 0);
			       run("Clear", "slice"); //...and delete it from that frame.
			   }
		    }
			n++; //track the frame number advancing
			run("Next Slice [>]");
			run("Select None");
		}
		
		//Find area of largest bleb
		setAutoThreshold("Triangle dark");
		setOption("BlackBackground", false);
		run("Convert to Mask", "method=Triangle background=Dark calculate");
		run("Analyze Particles...", "size=" + bleb_size + "-Infinity show=Overlay display clear stack");
		collectAreas("largest_bleb");
		collectSummaryStats("largest_bleb");
		run("Labels...", "color=green font=" + (width/32) + " show"); //label each large bleb with an overlay and a large green number
		rename(data_name + "_largest_bleb");
		saveAs("tiff", source + data_name + "_largest_bleb.tif");
		run("Read and Write Excel", "file=[" + source + data_name + "_excel.xlsx] sheet=large_blebs dataset_label=largest_blebs");
		if (choose_xls) {
			run("Read and Write Excel", "file=[" + expt_excel + "] sheet=" + sub_name + " dataset_label=" + data_name + "_largest_blebs");
		}
		Table.rename("Results", data_name + "_largest_bleb_results");
		saveAs("results", source + data_name + "_largest_bleb_results.csv");
		run("Close");
	}
	compareAreas();
	
	run("Close");
	run("Collect Garbage");
	run("Close All");
	setBatchMode(false);
}

