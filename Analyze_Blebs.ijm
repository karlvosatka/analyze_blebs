////
//// Analyze_Blebs
////
//// Semi-automated bleb analysis plugin
//// Vosatka, KW et al. (2021)
//// Version 1.2
//// Last updated 11-08-2021 by Karl Vosatka
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
//// to add -
//// make MPP an array from a string to house all previous conversion rates. make system for remembering and switching based on scope and chosen label
//// auto-open windows needed for plugin output file-based runs using same logic as tracer auto-open. implement for og source and curr source
//// make a more intuitive and user friendly way to use individual bleb analysis so that people can go back and re-run it. consider removing previous blebs from images? maybe save an indiv_bleb image that tracks this?
//// consider a method to autocheck what number bleb is being analyzed for individual bleb analysis

var source = "";
var og_source = "";
var data_name = "";
var sub_name = "";
var extension = "";
var chosen_threshold = "";
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
var bleb_rate = call("ij.Prefs.get", "blebs.bleb_rate", 1);
var bleb_unit = call("ij.Prefs.get", "blebs.bleb_unit", "sec");
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
i = 0;
while(i == 0) {
	if(nImages == 0) {
		Dialog.create("Open an Image Series");
		Dialog.addMessage("Please select an image time series for analysis");
		Dialog.addFile("", "");
		Dialog.show();

		open(Dialog.getString());
	}
	else {
		i = 1;
	}
}

//Find values used throughout plugin that are dependent on image scale
getDimensions(width, height, channels, slices, frames);
zoomFinder();
trash = zoomChecker();
lineWidth();
last_slice = frames;

//Decide if running multiple cells
mult = startUp();
if(mult) {
	images = getList("image.titles");
	Dialog.createNonBlocking("Cells");
	Dialog.addNumber("Number of cells to analyze: ", 1);
	Dialog.addMessage("Cells are labelled from 1 by default");
	Dialog.addCheckbox("Use custom labels", false);
	Dialog.show();
	
	num_cells = Dialog.getNumber();
	custom_label = Dialog.getCheckbox();
	labels = newArray(num_cells);
	
	if(custom_label) {
		Dialog.createNonBlocking("Labels");
		Dialog.addMessage("Enter your label for each cell");
		for(i=0;i<labels.length;i++) {
			Dialog.addString("Label " + i + 1, "");
		}
		Dialog.show();
	
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


function doNaming() {
	data_name = File.getNameWithoutExtension(source + getTitle());
	extension = substring(getTitle(), lengthOf(data_name));
	sub_name = data_name;
	if (endsWith(data_name, ".tif")) { //remove 
		data_name = substring(data_name, 0, lastIndexOf(data_name, "."));
		sub_name = data_name;
	}
	if (indexOf(data_name, "method") >= 0) { //store the name of the threshold that was used
		chosen_threshold = substring(data_name, lastIndexOf(data_name, "method"), lengthOf(data_name));
		data_name = substring(data_name, 0, lastIndexOf(data_name, "_method"));
		sub_name = data_name;
	}
	if (endsWith(data_name, "_all_blebs")||endsWith(data_name, "_whole_cell")||endsWith(data_name, "_largest_bleb")) {
		data_name = substring(data_name, 0, lastIndexOf(data_name, "_"));
		data_name = substring(data_name, 0, lastIndexOf(data_name, "_"));
		sub_name = data_name;
	}
	if (endsWith(data_name, "_threshold")||endsWith(data_name, "_tracer")) {
		data_name = substring(data_name, 0, lastIndexOf(data_name, "_"));
		sub_name = data_name;
	}
	data_name = replace(data_name, " ", "_");
	sub_name = data_name;
	if (lengthOf(data_name) >= 31) {
		sub_name = substring(data_name, lengthOf(data_name) - 30);
	}
}

function startUp() {
	getSkips();
	source = getInfo("image.directory"); //store the location of the original file in memory
	og_source = source;
	doNaming();//store the name of the original file in memory
	resetMinAndMax;
	run("Enhance Contrast", "saturated=0.35");
	run("Set... ", "zoom=" + zoom*100);
	run("Input/Output...", "jpeg=85 gif=-1 file=.csv use_file copy_column copy_row save_column save_row"); //standardize output settings
	
	Dialog.createNonBlocking("Startup Options");
	Dialog.addMessage("Enter the label you would like added to each data file and choose the folder to save plugin outputs\nNote: All spaces for data file names will be replaced with underscores");
	Dialog.addString("Data File Name:", data_name, 30); //decide on naming of plugin output files
	Dialog.addDirectory("Data File Folder:", source); //decide on saving location
	Dialog.addCheckbox("Add data to an excel file for the experiment (recommended)", choose_xls); //decide on auto-excel export
	Dialog.addFile("Excel File Location:", expt_excel); //find and choose Excel file
	Dialog.addCheckbox("Analyze Leader Bleb", leader_bleb);
	Dialog.addCheckbox("Individual Bleb Analysis", indiv_bleb);
	
	if (skip_count == 0) {
		Dialog.addCheckbox("Use previous image formatting options (Z isolation, micron conversion)", prev_settings);
	}
	if (skip_count <3) {
		Dialog.addCheckbox("Analyze multiple cells on the same image", false);
	}
	Dialog.addMessage("");
	Dialog.addCheckbox("Access plugin Options", pick_measures); //decide on whether or not to choose your own vectors to be measured on the images
	
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
	
	if(choose_xls) {
		i = 0;
		while (i == 0) {
			if (endsWith(expt_excel, ".xls")||endsWith(expt_excel, ".xlsx")) {
				i = 1;
			}
			else {
				Dialog.create("Experimental Excel File Warning");
				Dialog.addMessage("You didn't select an excel file (.xls or .xlsx)");
				Dialog.addFile("Excel File Location: ", expt_excel); //find and choose Excel file
				oops_excel = newArray("Excel file chosen", "I don't want an experimental Excel file");
				Dialog.addRadioButtonGroup("", oops_excel, 2, 1, oops_excel[0]);
				Dialog.show();
	
				if(Dialog.getRadioButton() == oops_excel[1]) {
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
		
		if(channels > 1) { //if the data is a multi-color stack...
			//Select the color channel for analysis
			window_name = getTitle();
			new_windows = newArray(channels);
			resetMinAndMax;
			run("Split Channels");
			for(i = 0; i < channels; i++) {
				selectWindow("C" + (i + 1) + "-" + window_name);
				new_windows[i] = getTitle();
				
				run("Enhance Contrast", "saturated=0.35");
				run("Set... ", "zoom=" + zoom*100);
			}
			
			Dialog.createNonBlocking("Color Channel");
			Dialog.addMessage("Choose your preferred color channel");
			Dialog.addChoice("", new_windows);
			Dialog.setLocation(getDbX(), (screenHeight/2-200));
			Dialog.show();
			
		    chosen_name = Dialog.getChoice();
		    for(i = 0; i < channels; i++) {
		    	selectWindow("C" + (i + 1) + "-" + window_name);
		    	if(getTitle() != chosen_name) {
		    		close();
		    	}
		    }
		    selectWindow(chosen_name);
		}
		
		if (slices > 1 && slices != nSlices) { //if the image has multiple Z planes...
			//Choose your preferred method for isolating one Z frame
			if (!prev_settings) { //You only get this choice if you chose not to use previous settings.
				Dialog.createNonBlocking("Z Stack Method");
				Dialog.addMessage("Select the preferred method for isolating Z plane");
				z_options = newArray("Select a single Z plane", "Collapse Z planes");
				Dialog.addRadioButtonGroup("", z_options, 2, 1, z_options[0]);
				Dialog.setLocation(getDbX(), (screenHeight/2-200));
				Dialog.show(); 
				z_choice = Dialog.getRadioButton();
			}
			if(z_choice == "Select a single Z plane") { //if you want to choose a single Z plane...
				window_name = getTitle();
				new_windows = newArray(slices);
				resetMinAndMax;
				run("Deinterleave", "how=" + slices);//...enter the number of z planes in the image
				
				for(i = 0; i < slices; i++) {
					selectWindow(window_name + " #" + (i + 1));
					new_windows[i] = getTitle();
					
					run("Enhance Contrast", "saturated=0.35");
					run("Set... ", "zoom=" + zoom*100);
				}
				
				Dialog.createNonBlocking("Z plane");
				Dialog.addMessage("Choose your preferred Z plane");
				Dialog.addChoice("", new_windows);
				Dialog.setLocation(getDbX(), (screenHeight/2-200));
				Dialog.show();
				
				chosen_name = Dialog.getChoice();
				for(i = 0; i < slices; i++) {
					selectWindow(window_name + " #" + (i + 1));
					if(getTitle() != chosen_name) {
						close();
					}
				}
				selectWindow(chosen_name);
			}
			
			else if(z_choice == "Collapse Z planes") { //if you want to combine all Z planes into one stacked image...
				if(!prev_settings) {
					Dialog.createNonBlocking("ZProjection");
					Dialog.addNumber("Start slice:  ", 1);
					Dialog.addNumber("Stop slice:  ", slices);
					z_proj_options = newArray("Average Intensity", "Max Intensity", "Min Intensity", "Sum Slices", "Standard Deviation", "Median");
					Dialog.addChoice("Projection Type  ", z_proj_options, z_proj_options[1]);
					Dialog.setLocation(getDbX(), (screenHeight/2-200));
					Dialog.show();
					//select from ImageJ's standard Z-collapsing options, and enter the range of Z planes you would like to collapse
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
		
		getPixelSize(unit, pw, ph);
		if (unit == "pixels"||pw == 1) { //if the image is not scaled properly in microns...
			//...convert image to microns
			if(!prev_settings||MPP == "") { //You only have to enter your conversion rate if you chose to do so earlier or if you have yet to enter your conversion rate previously
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

function getDbX() {
	getLocationAndSize(ix, iy, iw, ih);
	pop_up = ix + iw + screenHeight/30;
	return pop_up;
}

function sliceKeeper(all, type) {
		Dialog.createNonBlocking("Select Relevant Frames");
		if(type == "bleb") {
			Dialog.addMessage("Enter the slice range/time frame for this bleb");
		}
		else {
			Dialog.addMessage("Enter the slice range/time frame of interest"); //use this to eliminate frames where the cell isn't present or has died
		}
		Dialog.addNumber("First Slice", first_slice);
		Dialog.addNumber("Last Slice", nSlices);
		Dialog.addNumber("Keep every nth frame", interval); //e.g. keep every 2nd frame, every 3rd frame, etc.
		Dialog.show();
	
		first_slice = Dialog.getNumber();
		last_slice = Dialog.getNumber();;
		interval = Dialog.getNumber();;;

		if (!all) {
			window_name = getTitle();
			run("Slice Keeper", "first=" + first_slice +" last=" + last_slice + " increment=" + interval);
			
			close(window_name);
			run("Set... ", "zoom=" + zoom*100);
			rename(window_name);
		}
		else {
			images = getList("image.titles");
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

function tracerFinder() {
	n = 0;
	while(n == 0) {
		images = getList("image.titles");
		tracer_check = false;
		tracer_id = "";
		for(i = 0; i<images.length; i++) {
			if(indexOf(images[i], "tracer") >= 0) { //check all images for tracer
				tracer_check = true;
				selectWindow(images[i]);
				tracer_id = getImageID();
			}
		}
			
		if(!tracer_check) { //if it's not open...
			if(File.exists(source + File.separator + data_name + "_tracer.tif")) {
				open(source + File.separator + data_name + "_tracer.tif");
			}
			else if(File.exists(og_source + File.separator + data_name + "_tracer.tif")) {
				open(og_source + File.separator + data_name + "_tracer.tif");
				saveAs("tiff", source + data_name + "_tracer.tif");
			}
			else {
				Dialog.createNonBlocking("Open Tracer File");
				Dialog.addMessage("Please select the tracer file for this experiment.");
				Dialog.addFile("", "")
				Dialog.show();
				//...get prompted on a loop until it is open
				open(Dialog.getString());
			}
		}
		else { //when tracer is open...
			selectImage(tracer_id);
			run("Set... ", "zoom=" + zoom*100);
			tracer_name = substring(getTitle(), 0, indexOf(getTitle(), "_tracer"));
			if(tracer_name != data_name) {
				rename(data_name + "_tracer.tif"); //...make the name match
				saveAs("tiff", source + data_name + "_tracer.tif"); //...and resave the version as needed
			}
			n = 1;
		}
	}
}

function getSkips() {
	images = getList("image.titles");
	all_check = false;
	whole_check = false;
	thresh_check = false;
	tracer_check = false;
	
	for(i = 0; i<images.length; i++) {
		run("Select None");
		run("Set... ", "zoom=" + zoom*100);
		resetMinAndMax;
		run("Enhance Contrast", "saturated=0.35");
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

function invertChecker(window) { //checks pixel intensity in each corner to see if image is properly inverted. can be toggled in settings.
	selectWindow(window);
	makeRectangle(0,0,2,2);
	getStatistics(area,mean,min);
	up_left = min;
	
	makeRectangle(width/2-1, 0, 2,2);
	getStatistics(area,mean,min);
	up = min;
	
	makeRectangle(width-2,0,2,2);
	getStatistics(area,mean,min);
	up_right = min;
	
	makeRectangle(0, height/2-1,2,2);
	getStatistics(area,mean,min);
	left = min;
	
	makeRectangle(width-2,height/2-1,2,2);
	getStatistics(area,mean,min);
	right = min;
	
	makeRectangle(0,height-2,2,2);
	getStatistics(area,mean,min);
	bottom_left = min;
	
	makeRectangle(width/2-1,height-2,2,2);
	getStatistics(area,mean,min);
	bottom = min;
	
	makeRectangle(width-2,height-2,2,2);
	getStatistics(area,mean,min);
	bottom_right = min;
	
	run("Select None");
	
	corners = newArray(up_left,up,up_right,left,right,bottom_left,bottom,bottom_right);
	corners_num=0;
	for(i=0;i<8;i++) {
		if(corners[i] == 0) {
			corners_num++;
		}
	}
	
	if(corners_num < 4) {
	run("Invert", "stack");
	waitForUser("The plugin detected an inversion error. \nIf the cell doesn't show up as black on a white background, run Edit>Invert, then continue");
	}
}

function sizeExclusion(type, default_size, num_label) {
	Dialog.createNonBlocking("Minimum Size Cut-Off For " + type + " Analysis");
	Dialog.addMessage("Enter a size for the " + type + " in microns squared. All objects below this size will be excluded.\nFor example, for a 60X objective, a size exclusion of 200 microns squared per cell and 10 microns squared per bleb is recommended.");
	Dialog.addMessage("If you don't want to exclude any objects, enter 0.\nHowever, note that noise that is not easily detected by eye may be counted in this case."); //It's highly recommended that you choose a number greater than zero. 
	//In most cases, small artifact objects that are not easily seen by eye will be present on your data file, and if you choose zero as your
	//exclusion size, they will be measured and counted as blebs. The size of 10 microns squared catches even the smallest blebs in most cases.
	Dialog.addNumber(num_label + " Size", default_size);
	Dialog.show();
	
	obj_size = Dialog.getNumber();
	return obj_size
}

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
		
		measure_read = newArray("Area", "Mean gray value", "Standard deviation", "Modal gray value", "Min & max gray value", "Centroid", "Center of mass", "Perimeter", "Bounding rectangle", "Fit ellipse", "Shape descriptors", "Feret's diameter", "Integrated density", "Median", "Skewness", "Kurtosis", "Area fraction", "Stack position", "Limit to threshold", "Display label", "Invert Y coordinates", "Scientific notation", "Add to overlay", "NaN empty cells"); 
		measure_read_a = Array.slice(measure_read, 0, 18);
		measure_bool_a = Array.slice(measure_bool, 0, 18);
		measure_read_b = Array.slice(measure_read, 18, 24);
		measure_bool_b = Array.slice(measure_bool, 18, 24);
		
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

		getPixelSize(unit, pw, ph);
		size = (getHeight()*getWidth()*pw*ph)/20;
		Dialog.addMessage("Minimum Sizes for Cell Parts");
		Dialog.addSlider("Cell Size", 1, size, cell_size);
		Dialog.addSlider("Bleb Size", 1, size/10, bleb_size);
		Dialog.addCheckbox("Cell Body Default (0.25 * Cell Size)", true);
		Dialog.addSlider("Cell Body Size", 1, size, 0.25*cell_size);

		Dialog.addCheckbox("Restore Defaults", false);
		Dialog.addHelp("https://imagej.nih.gov/ij/docs/menus/analyze.html#set");
		Dialog.show();
		
		decimals = Dialog.getNumber();
		cell_size = Dialog.getNumber();
		bleb_size = Dialog.getNumber();
	
		//Record decisions as a boolean array
		for (i=0; i<18; i++) {
			measure_bool_a[i] = Dialog.getCheckbox();
		}
		for (i=0; i<6; i++) {
			measure_bool_b[i] = Dialog.getCheckbox();	
		}
		measure_bool = Array.concat(measure_bool_a, measure_bool_b);
		
		invert_check = Dialog.getCheckbox();
		auto_pos = Dialog.getCheckbox();
		if(Dialog.getCheckbox()) cb_size = Dialog.getNumber();
		call("ij.Prefs.set", "blebs.auto_pos", auto_pos);
		hand_choice = Dialog.getRadioButton();
		defaults = Dialog.getCheckbox();

		if(hand_choice == "Right-handed (default)") {
			handed = "1, 1, 1, 1";
		}
		else if (hand_choice == "Left-handed") {
			handed = "0, 0, 0, 0";
		}
		else {
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
			bleb_rate = 1;
			call("ij.Prefs.set", "blebs.bleb_rate", bleb_rate);
			bleb_unit = "sec";
			call("ij.Prefs.set", "blebs.bleb_unit", bleb_unit);
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

	t = 0;
	while (t==0){
		selectWindow("threshold options");
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
			drawCell();
			t = 1;
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
				t=1; //...and move to the whole cell step
			}
			else if (rethresh) {
				close("despeckled");
				close("thresh_choice");
				selectWindow(data_name + "_tracer.tif");
				run("Duplicate...", "title=despeckled duplicate");
				run("Set... ", "zoom=" + zoom*100);
			}
		}
	}
}

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
	edit_opt = newArray("Draw the cell", "Time course is complete");
	i = 0;
	while (i == 0) {
		Dialog.createNonBlocking("Trace cell");
		Dialog.addMessage("Outline the cell on the despeckled image");
		Dialog.addMessage("Indicate when finished");
		Dialog.addRadioButtonGroup("", edit_opt, 2, 1, edit_opt[0]);
		if (auto_pos) Dialog.setLocation(db_x, db_y);
		Dialog.show();
		edit_choice = Dialog.getRadioButton();
	
		selectWindow("despeckled");
		if(edit_choice == edit_opt[0]&& is("area")) {
			run("Draw", "slice"); //draws a line that expands the area you chose by a few pixels. helps because the selection line is very thin and hard to accurately use.
			run("Fill", "slice");
			run("Clear Outside", "slice"); //colors in the area you traced as white, labelling it as part of a cell.
		}
		else if(edit_choice == edit_opt[1]) {
			selectWindow("despeckled");
			run("Select None");
			setOption("BlackBackground", false);
			setAutoThreshold("Triangle dark");
			run("Convert to Mask", "method=Triangle background=Dark");
			run("Set... ", "zoom=" + zoom*100);
			chosen_threshold = "method=Drawn";
			resetThreshold;
			i = 1;
		}
		if (!zoomChecker() && auto_pos) {
			orgWindows(left[0], right[0], "trace", auto_pos, true);
		}
		setTool("freehand");
	}
	selectWindow("despeckled");
	rename(data_name + "_threshold_" + chosen_threshold + ".tif");
	saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
}

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

function widthToZoom(sw) {
	z_set = newArray(4, 3, 2, 1.5, 1, 0.75, 0.5, (1/3), 0.25, (1/6), 0.125);
	for(i = 0; i < z_set.length; i++) {
		if(z_set[i] < sw) {
			new_z = z_set[i];
			return new_z;
		}
	}
}

function zoomChecker() {
	images = getList("image.titles");
	if (isOpen("threshold options")) images = Array.deleteValue(images, "threshold options"); //catches case during fill holes when threshold options is open
	check = true;
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

function fillHoles() {
	if(!isOpen("despeckled")) {
		selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
		rename("despeckled");
	}
	
	holeQ1 = newArray("Yes", "No");
	selectWindow("despeckled");
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
			edit_opt = newArray("Draw the cell outline", "Time course is complete");
			i = 0;
			
			while (i == 0) {
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
		    	if(!zoomChecker() && auto_pos) {
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

function separateNoise(input_size) {
	selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
	run("Analyze Particles...", "size="+ input_size +"-Infinity show=Masks clear stack");
	close(data_name + "_threshold_" + chosen_threshold + ".tif");
	run("Set... ", "zoom=" + zoom*100);
	rename(data_name + "_threshold_" + chosen_threshold + ".tif");
	
	noise = newArray("There is noise attached to the cell", "No noise is attached to the cell");
	//Remove any objects attached to the cell
	Dialog.createNonBlocking("Attached Noise Objects");
	Dialog.addMessage("Check all frames to see if anything is touching the cell of interest\n\nThis could be background noise or another cell"); //here noise is anything large enough and attached means its touching the cell.
	Dialog.addRadioButtonGroup("", noise, 2, 1, noise[1]);
	Dialog.setLocation(getDbX(), (screenHeight/2-200));
	Dialog.show();
	noise_ans = Dialog.getRadioButton();
	
	
	if (noise_ans == noise[0]) {
		orgWindows(left[2], right[2], "attached", auto_pos, false);
		setForegroundColor(255, 255, 255);
		setBackgroundColor(255, 255, 255);
		setTool("freeline");
		run("Line Width...", "line=" + Math.ceil(Math.sqrt(width*height)/205));
		i = 0;
		edit_opt = newArray("Separate noise object", "Time course is complete");
		while (i == 0) {
			
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
			if(!zoomChecker() && auto_pos) {
				orgWindows(left[2], right[2], "attached", auto_pos, true);
			}
			setTool("freeline");
		}
		saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
	}
}

function multiThresh() {
	root_source = source;
	og_name = data_name;
	og_threshold = chosen_threshold;
	Dialog.createNonBlocking("Multiple Cells on Threshold");
	Dialog.addMessage("Indicate which cells are present on the threshold");
	thresh_mult = newArray(labels.length);
	labels_cell = Array.copy(labels);
	for (l = 0; l < labels_cell.length; l++) {
		labels_cell[l] = "Cell '" + labels_cell[l] + "' is present on threshold";
	}
	Array.fill(thresh_mult, false);
	Dialog.addCheckboxGroup(labels_cell.length, 1, labels_cell, thresh_mult);
	Dialog.show();
	
	for(l = 0; l < thresh_mult.length; l++) {
		thresh_mult[l] = Dialog.getCheckbox();
	}

	for (l = 0; l < thresh_mult.length; l++) {
		selectWindow(og_name + "_tracer.tif");
		rename(batch_names[l] + "_tracer.tif");
		selectWindow(og_name + "_threshold_" + chosen_threshold + ".tif");
		rename(batch_names[l] + "_threshold_" + chosen_threshold + ".tif");
		source = batch_sources[l];
		data_name = batch_names[l];
		setMeasures();
		if(thresh_mult[l]) {
			Dialog.createNonBlocking("Choose Cell " + labels[l]);
			Dialog.addMessage("In the following steps, click on cell " + labels[l] + "\non the threshold image to isolate it");
			Dialog.addCheckbox("Choose a different frame range", false);
			Dialog.show();
			
			if(Dialog.getCheckbox()) {
				selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
				sliceKeeper(true, "cell");
				selectWindow(data_name + "_tracer.tif");
				saveAs("tiff", source + data_name + "_tracer.tif");
				selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
				setMeasures();
			}
			threshPick(cell_size, "cell", data_name + "_threshold_" + chosen_threshold + ".tif");
			saveAs("tiff", source + data_name + "_threshold_" + chosen_threshold + ".tif");
		}
		else {
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
				setMeasures();
			}
			
			if(m_thresh_rechoice == m_thresh_redo[0]) {
				drawCell();
			}
			else if(m_thresh_rechoice == m_thresh_redo[1]) {
				threshOptions();
			}
		}
		setMeasures();
			sub_name = data_name;
		if (lengthOf(data_name) >= 31) {
			sub_name = substring(data_name, lengthOf(data_name) - 30);
		}
		cellPartition(true);
		close("*");
		waitForUser("Analysis of cell " + labels[l] + " is complete!");
		open(root_source + File.separator + og_name + "_tracer.tif");
		run("Set... ", "zoom=" + zoom*100);
		resetMinAndMax;
		run("Enhance Contrast", "saturated=0.35");
		open(root_source + File.separator + og_name + "_threshold_" + og_threshold + ".tif");
		run("Set... ", "zoom=" + zoom*100);
	}
}

function threshCheck() {
	selectWindow(data_name + "_threshold_" + chosen_threshold + ".tif");
	run("Analyze Particles...", "size=" + cell_size + "-Infinity clear stack");
	return (getValue("results.count") == nSlices);
}

function threshPick(input_size, type, window) {
	if(isOpen("Synchronize Windows")) {
		waitForUser("Click *UN*synchronize all in Synchronize Windows");
	}
	setForegroundColor(255, 255, 255);
	setBackgroundColor(255, 255, 255);
	selectWindow(window);
	for(f=1; f <= nSlices; f++) {
		setSlice(f);
		num_large_objs = 0;
		setAutoThreshold("Triangle light");
		run("Analyze Particles...", "size=" + input_size + "-Infinity clear add slice");
		count = roiManager("count");
		if(count > 1) {
			run("Labels...", "color=blue font=" + (width/32) + " show");
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

function blebTracker() {
	first_slice = 1;
	last_slice = nSlices;
	i = 1;
	while(true) {

		selectWindow(data_name + "_all_blebs.tif");
	
		Dialog.createNonBlocking("Bleb Tracking");
		Dialog.addMessage("Set bleb frame range, frame rate, time unit, and size.");
		Dialog.addNumber("Range for bleb #", i);
		Dialog.addNumber("First Frame: ", first_slice, 0, 3, "");  
		Dialog.addNumber("Last Frame: ", last_slice, 0, 3, "");
		units = newArray("sec", "min");
		Dialog.addNumber("Frame Rate: ", bleb_rate, 0, 3, "time units per frame"); 
		Dialog.addRadioButtonGroup(" Time Unit:", units, 1, 2, units[0]);
		Dialog.addCheckbox("Bleb tracking is finished", false);
		Dialog.show();

		if (Dialog.getCheckbox()) {
			break;
		}
		bleb_num = Dialog.getNumber();
		first_slice = Dialog.getNumber();;
		last_slice = Dialog.getNumber();;;
		bleb_rate = Dialog.getNumber();;;;
		bleb_unit = Dialog.getRadioButton();

		call("ij.Prefs.set", "blebs.bleb_rate", bleb_rate);
		call("ij.Prefs.set", "blebs.bleb_unit", bleb_unit);

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
		for (row=0; row<nResults; row++) {
			time = bleb_rate * (getResult("Slice", row)-1);
    		setResult(bleb_unit, row, time);
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

function zoomFinder() {
	zh_lb = screenHeight/(getHeight()*2.5);
	zh_ub = screenHeight/(getHeight()*1.5);
	zw_b = (screenWidth-377)/(getWidth()*2);
	getLocationAndSize(ax, ay, w, h);
	sw = w / getWidth();
	z_set = newArray(4, 3, 2, 1.5, 1, 0.75, 0.5, (1/3), 0.25, (1/6), 0.125);
	
	if (sw > zh_ub) {
		for(i = 0; i < z_set.length; i++) {
			if(z_set[i] < zh_ub) {
				zoom = z_set[i];
				return;
			}
		}
	}
	else if (sw > zw_b) {
		for(i = 0; i < z_set.length; i++) {
			if(z_set[i] < zw_b) {
				zoom = z_set[i];
				return;
			}
		}
	}
	else if (sw < zh_lb) {
		for(i = z_set.length - 1; i >=0 ; i--) {
			if(z_set[i] > zh_lb) {
				zoom = z_set[i];
				return;
			}
		}
	}
	else return;
}

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

function lineWidth() {
	line_w = Math.ceil(Math.sqrt(width*height)/205);
	if (line_w < 3) {
		line_w = 3;
	}
}

function rawToThresh(mult) {

	if(skip_count > 1) { //We want to make sure the tracer is open if we're working with plugin output files
		tracerFinder();
		
	}
	
	if(skip_count == 0||((indexOf(rest_of_name, "_tracer") >=0)&&mult)) {
		//Eliminate frames where the cell has left
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
			waitForUser("Hold the alt key and click on a spot that is representative of background signal levels"); 
		
			i = 0;
			while (i == 0) {
				setTool("freehand");
				RLO = newArray("Remove Object", "Reset Background Color", "Time course is complete");
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
		i = 0;
		edit_opt = newArray("Remove the cell body", "Time course is complete");
		selectWindow(data_name + "_tracer.tif");
		while (i == 0) {
			Dialog.createNonBlocking("Remove cell body");
			Dialog.addMessage("Circle the cell body so that it can be removed");
			Dialog.addMessage("Indicate when finished");
			Dialog.addRadioButtonGroup("", edit_opt, 2, 1, edit_opt[0]);
			if (auto_pos) Dialog.setLocation(db_x, db_y);
			Dialog.show(); //circle the cell body in this step. It will be removed from the image to isolate the blebs. You can edit the same
			//frame as many times as is necessary. Anything you circle before selecting "Circle cell body" will be removed.
			edit_choice = Dialog.getRadioButton();
			selectWindow("cell_mask");
			
			if(edit_choice == edit_opt[0] && is("area")) {
				run("Draw", "slice"); //draws a thin line around the outline you made. This can prevent errors where the outline doesn't properly separate
				//blebs from each other or from the cell body
				run("Clear", "slice");
				run("Next Slice [>]");
			}
			if(edit_choice == edit_opt[1]) {
				run("Select None");
			    i = 1;
			}
			if (!zoomChecker() && auto_pos) {
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
		run("Analyze Particles...", "show=Overlay display clear summarize stack"); //adds an overlay to the image for each bleb that was included as a bleb.
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
		Table.rename("Summary of Mask of cell_mask", data_name + "_all_blebs_summ");
		saveAs("results", source + data_name + "_all_blebs_summ.csv"); //This summary file, labelled the "all blebs summ" file, lists the number of
		//blebs that occur on each frame, as well as the total area of the blebs on each frame.
		run("Close");
	}
	
	else {
		whole_check = false;
		all_check = false;
		n = 0;
		while(n == 0) {
			images = getList("image.titles");
			
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
				else {
					Dialog.createNonBlocking("Missing Whole Cell Image");
					Dialog.addMessage("Open the whole_cell image to create the cell body and largest bleb images");
					Dialog.addFile("Whole Cell Image: ", source);
					Dialog.show();
					whole_loc = Dialog.getString();
					open(whole_loc);
					rename(data_name + "_whole_cell.tif");
					saveAs("tiff", source + data_name + "_whole_cell.tif");
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
		
		if(indiv_bleb) {
			setBatchMode(false);
			selectWindow(data_name + "_all_blebs.tif");
			run("Set... ", "zoom=" + zoom*100);
			blebTracker();
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
		
		images = getList("image.titles");
		mask_check = false;
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
		while (n<=nSlices-1){ //n corresponds to the frame number
			run("Analyze Particles...", "size=" + bleb_size + "-Infinity show=Nothing clear record");
			area=0;
		    for (i=0; i<nResults; i++) {  //i corresponds to the number of the blebs on each frame
		       count = getResult('Area', i);
		       if (count>area) area=count; //scanning through the results, whichever bleb in each frame has the highest area on each frame has its
		       // area value saved in the "area" variable
		       }
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
			n++; //proceed through each frame
			run("Next Slice [>]");
			run("Select None");
		}
		
		//Find area of largest bleb
		setAutoThreshold("Triangle dark");
		setOption("BlackBackground", false);
		run("Convert to Mask", "method=Triangle background=Dark calculate");
		run("Analyze Particles...", "size=" + bleb_size + "-Infinity show=Overlay display clear summarize stack");
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
		Table.rename("Summary of " + data_name + "_all_blebs.tif", data_name + "_largest_bleb_summ");
		saveAs("results", source + data_name + "_largest_bleb_summ.csv"); //A summary file is saved here. This will indicate the data on a per-frame basis,
		//indicating the cases where a frame has no blebs and therefore no largest bleb
	}
	
	run("Close");
	run("Collect Garbage");
	run("Close All");
	setBatchMode(false);
}

