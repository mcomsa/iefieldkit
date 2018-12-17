//! version 0.1 12DEC2018  DIME Analytics dimeanalytics@worldbank.org

// Main syntax *********************************************************************************

cap program drop iecodebook
	program def  iecodebook

	version 13 // Required 13.1 due to use of long macros

	syntax [anything] using , [*]

	// Select subcommand
	gettoken subcommand anything : anything

	// Throw error if codebook exists
	if ("`subcommand'" == "template") {
		local file = subinstr(`"`using'"',"using","",.)
		cap confirm new file `file'
		if _rc != 0 {
			di as err "That template already exists. iecodebook does not allow you to overwrite an existing template,"
			di as err " since you may already have set it up. If you are {bf:sure} that you want to delete this template,"
			di as err `" you need to manually remove it from`file'. [iecodebook] will now exit."'
			exit
		}
	}

	// Make sure some command is specified
	if !inlist("`subcommand'","template","apply","append","export") {
		di as err "{bf:iecodebook} requires [template], [apply], [append], or [export] to be specified with a target [using] codebook. Type {bf:help iecodebook} for details."
	}

	// Execute subcommand
	iecodebook_`subcommand' `anything' `using' , `options'

end

// Template subroutine *********************************************************************************

cap program drop iecodebook_template
program iecodebook_template

	syntax [anything] [using] , [*]

	// Select the right syntax and pass through to templating options
	if `"`anything'"' == `""' {
		iecodebook apply `using' , `options' template
	}
	else {
		iecodebook append `anything' `using' , `options' template
	}

end

// Export subroutine *********************************************************************************

cap program drop iecodebook_export
	program 	 iecodebook_export

	syntax [anything] [using] [if] [in], [template(string asis)] [trim(string asis)]
qui {

	// Return a warning if there are lots of variables
	if `c(k)' >= 1000 di as err "This dataset has `c(k)' variables. This may take a long time! Consider subsetting your variables first."

	// Store current data and apply if/in via [marksample]
		tempfile allData
		save `allData' , emptyok

		marksample touse
		keep if `touse'
			drop `touse'

	// Template Setup
		if `"`anything'"' != "" {
			use `anything' , clear
		}

		if "`template'" != "" {
			local template_colon ":`template'" 	// colon for titles
			local template_us "_`template'" 	// underscore for sheet names
			local TEMPLATE = 1					// flag for template functions
		}
		else local TEMPLATE = 0

	// Set up temps
	preserve
		clear

		tempfile theLabels

		tempfile theCommands
			save `theCommands' , replace emptyok
	restore

	// Option to [trim] variable set to variables specified in selected dofiles
	if `"`trim'"' != `""' {
		// Initialize datafile of variable names
		unab theVarlist : *
		preserve
			clear

			tempfile a
				save `a' , replace emptyok

		// Stack up all the lines of code from all the dofiles in a dataset
		foreach dofile in `trim' {
				import delimited "`dofile'" , clear
				append using `a'
				tempfile a
					save `a' , replace
		}

		// Loop through every variable in the current dataset and put its name wherever it occurs
		local x = 1
		foreach item in `theVarlist' {
			local ++x
			gen v`x' = "`item'" if strpos(v1,"`item'")
		}

		// Collapse to one column to get every variable mentioned in any dofile
		collapse (firstnm) v* , fast
			gen n = 1
			reshape long v , i(n) // Reshape to column of varnames
			keep v
			drop if v == ""
			drop in 1

		// Loop over variable names to build list of variables to keep
		count
		forvalues i = 1/`r(N)' {

			local theNextVar = v[`i']
			local theKeepList = "`theKeepList' `theNextVar'"

		}

		// Restore and keep variables
		restore
			if "`theKeepList'" == "" {
				di as err "You are dropping all variables. This is not allowed. {bf:iecodebook} will now exit."
				exit
			}
			keep `theKeepList' // Keep only variables mentioned in the dofiles
			compress
			local savedta = subinstr(`"`using'"',".xlsx",".dta",.)
			local savedta = subinstr(`"`savedta'"',"using ","",.)
			save `savedta' , replace
	}

	// Create XLSX file with all current/remaining variable names and labels * use SurveyCTO syntax for sheet names and column names
	preserve

		// Record dataset info

			local allVariables
			local allLabels
			local allChoices

			foreach var of varlist * {
				local theVariable 	= "`var'"
				local theLabel		: var label `var'
				local theChoices	: val label `var'

				local allVariables 	`"`allVariables' "`theVariable'""'
				local allLabels    	`"`allLabels'   "`theLabel'""'
				local allChoices 	`"`allChoices'   "`theChoices'""'
			}

		// Write to new dataset

			clear

			local theN : word count `allVariables'

			local templateN ""
			if `TEMPLATE' {
				import excel `using' , clear first sheet("survey")

				count
				local templateN "+ `r(N)'"
			}

			set obs `=`theN' `templateN''

			gen name`template' = ""
				label var name`template' "name`template_colon'"
			gen label`template' = ""
				label var label`template' "label`template_colon'"
			gen choices`template' = ""
				label var choices`template' "choices`template_colon'"
			if `TEMPLATE' gen recode`template' = ""
				if `TEMPLATE' label var recode`template' "recode`template_colon'"

			forvalues i = 1/`theN' {
				local theVariable 	: word `i' of `allVariables'
				local theLabel		: word `i' of `allLabels'
				local theChoices	: word `i' of `allChoices'

				replace name`template' 		= `"`theVariable'"' 	in `=`i'`templateN''
				replace label`template' 	= `"`theLabel'"' 		in `=`i'`templateN''
				replace choices`template' 	= `"`theChoices'"' 	in `=`i'`templateN''
			}

		// Export variable information to "survey" sheet
		cap export excel `using' , sheet("survey") sheetreplace first(varl)
		local rc = _rc
		forvalues i = 1/10 {
			if `rc' != 0 {
				sleep `i'000
				cap export excel `using' , sheet("survey") sheetreplace first(varl)
				local rc = _rc
			}
		}
		if `rc' != 0 di as err "A codebook didn't write properly. This can be caused by Dropbox syncing the file or having the file open. Consider turning Dropbox syncing off or using a non-Dropbox location. You may need to delete the file and try again."
		if `rc' != 0 exit
	restore

	// Create value labels sheet

		// Fill temp dataset with value labels
		foreach var of varlist * {
			local theLabel : value label `var'
			if "`theLabel'" != "" {
				cap label save `theLabel' using `theLabels' ,replace
				if _rc==0 {
					preserve
					import delimited using `theLabels' , clear delimit(", modify", asstring)
					append using `theCommands'
						save `theCommands' , replace emptyok

					restore
				}
			}
		}

		// Clean up value labels for export * use SurveyCTO syntax for sheet names and column names
		use `theCommands' , clear

			count
			if `r(N)' > 0 {
				duplicates drop
				drop v2
				replace v1 = trim(subinstr(v1,"label define","",.))
				split v1 , parse(`"""')
				split v11 , parse(`" "')
				keep v111 v112 v12
				order v111 v112 v12

				rename (v111 v112 v12)(list_name value label)
			}
			else {
				set obs 1
				gen list_name = ""
				gen value = ""
				gen label = ""
			}

		// Export value labels to "choices" sheet
		cap export excel `using' , sheet("choices`template_us'") sheetreplace first(var)
		local rc = _rc
		forvalues i = 1/10 {
			if `rc' != 0 {
				sleep `i'000
				cap export excel `using' , sheet("choices`template_us'") sheetreplace first(var)
				local rc = _rc
			}
		}
		if `rc' != 0 di as err "A codebook didn't write properly. This can be caused by Dropbox syncing the file or having the file open. Consider turning Dropbox syncing off or using a non-Dropbox location. You may need to delete the file and try again."
		if `rc' != 0 exit

	// Reload original data
	use `allData' , clear

} // end qui
end

// Apply subroutine *********************************************************************************

cap program drop iecodebook_apply
	program 	 iecodebook_apply

	syntax [anything] [using] , [template] [drop] [survey(string asis)] [MISSingvalues(string asis)]
qui {
	// Setups

		if "`survey'" == "" local survey "current"

	// Template setup

		if "`template'" != "" {
			// Create empty codebook with "survey" variable
				preserve
					clear
					set obs 1
					gen survey = 0
						label var survey "Survey"
					iecodebook export `using'
				restore
			// Append current dataset
			tempfile current
			save `current' , replace
			iecodebook export `current' `using' , template(`survey')
		exit
		}

	// Apply codebook
	preserve

		// Loop over survey sheet and accumulate rename, relabel, recode, vallab

			import excel `using' , clear first sheet(survey) allstring

			count
			forvalues i = 1/`r(N)' {
				local theName		= name`survey'[`i']
		    	local theRename 	= name[`i']
				local theLabel		= label[`i']
				local theChoices	= choices[`i']
				local theRecode		= recode`survey'[`i']

				if ("`drop'" != "" & "`theRename'" == "") | ("`theRename'" == "drop") local allDrops "`allDrops' `theName'"
				if "`theRename'" != "" & "`theName'" 	!= "" 	local allRenames1 	= `"`allRenames1' `theName'"'
				if "`theRename'" != "" & "`theName'" 	!= "" 	local allRenames2 	= `"`allRenames2' `theRename'"'
				if "`theRename'" != "" & "`theLabel'" 	!= "" 	local allLabels 	= `"`allLabels' `"label var `theName' "`theLabel'" "' "'
				if "`theRename'" != "" & "`theChoices'" != "" 	local allChoices 	= `"`allChoices' "label val `theName' `theChoices'""'
				if "`theRename'" != "" & "`theRecode'" 	!= "" 	local allRecodes 	= `"`allRecodes' "recode `theName' `theRecode'""'
			}

		// Loop over choices sheet and accumulate vallab definitions

			// Prepare list of value labels needed.

				drop if choices == ""
				cap duplicates drop choices, force

				count
				if `r(N)' == 1 {
					local theValueLabels = choices[1]
				}
				else {
					forvalues i = 1/`r(N)' {
						local theNextValLab  = choices[`i']
						local theValueLabels `theValueLabels' `theNextValLab'
					}
				}

			// Prepare list of values for each value label.

				import excel `using', first clear sheet(choices) allstring
					tempfile choices
						save `choices', replace

				foreach theValueLabel in `theValueLabels' {
					use `choices', clear
					keep if list_name == "`theValueLabel'"
					local theLabelList "`theValueLabel'"
						count
						local n_vallabs = `r(N)'
						forvalues i = 1/`n_vallabs' {
							local theNextValue = value[`i']
							local theNextLabel = label[`i']
							local theLabelList_`theValueLabel' `" `theLabelList_`theValueLabel'' `theNextValue' "`theNextLabel'" "'
						}
					// Add missing values if requested
					local theLabelList_`theValueLabel' `" `theLabelList_`theValueLabel'' `missingvalues' "'
				}

	// Back to original dataset to apply changes from codebook
	restore

		// Define value labels

			foreach theValueLabel in `theValueLabels' {
				label def `theValueLabel' `theLabelList_`theValueLabel'', replace
				}

		// Drop leftovers if requested
		cap drop `allDrops'

		// Apply all recodes, choices, and labels
		foreach type in Recodes Choices Labels {
			foreach change in `all`type'' {
				cap `change'
				if 		_rc == 181 			 	di as err `"Variable `: word 3 of `change'' is a string and cannot have a value label."'
				else if _rc == 111 			 	di as err `"Variable `: word 3 of `change'' was not found."'
				// Do nothing on survey variable - TODO: stop the survey variable being implemented on a single dataset?
				else if "`=lower("`type'")'" == "labels" & `"`change'"' == `"label var  "Survey" "' {
					}
				// Generic error message
				else if _rc != 0 & _rc != 100 	di as err `"One of your `=lower("`type'")' failed: check `change' in the codebook."'
			}
		}

		// Rename variables and catch errors
		cap rename (`allRenames1') (`allRenames2')
			if _rc != 0 {
				di as err "That codebook contains a rename conflict. Please check and retry. iecodebook will exit."
				rename (`allRenames1') (`allRenames2')
			exit
			}
} // end qui
end

// Append subroutine *********************************************************************************

cap program drop iecodebook_append
	program 	 iecodebook_append

	syntax [anything] [using] , surveys(string asis) [template] [noDROP] [*]
qui {

	// Optional no-drop
	if "`drop'" == "" {
		local drop "drop"
	}
	else {
		di as err "You have turned off the [drop] default, which means you are forcing all variables to be appended even if you did not manually harmonize them."
		di as err "Make sure to check the resulting dataset carefully. Forcibly appending data, especially of different types, may result in loss of information."
		local drop ""
	}

	// Final dataset setup

		clear
		tempfile final_data
			save `final_data' , replace emptyok

	// Template setup

		if "`template'" != "" {
			// create empty codebook
			preserve
				clear
				set obs 1
				gen survey = 0
					label var survey "Survey"
				iecodebook export `using'
			restore
			// append one codebook per survey
			local x = 0
			foreach survey in `surveys' {
				local ++x
				local filepath : word `x' of `anything'
				iecodebook export "`filepath'" `using' , template(`survey')
			}
		exit
		}

	// Loop over datasets and apply codebook

		local x = 0
		foreach dataset in `anything' {
			local ++x
			local survey : word `x' of `surveys'
			use `dataset' , clear
			iecodebook apply `using' , survey(`survey') `drop' `options'

			gen survey = `x'
			tempfile next_data
				save `next_data' , replace
			use `final_data' , clear
			append using `next_data'
				label def survey `x' "`survey'" , add
				label val survey survey
				save `final_data' , replace emptyok
		}

	// Final codebook

		local using = subinstr(`"`using'"',".xlsx","_appended.xlsx",.)
		iecodebook export `using'

		use `final_data' , clear
} // end qui
end

// Have a lovely day!
