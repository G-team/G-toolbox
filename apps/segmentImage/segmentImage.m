function segtoolHandle = segmentImage(varargin)
% SEGMENTIMAGE: Interactive App for exploration of segmentation options
%
% Segmentation masks and recreation steps (i.e., "code") are exportable to
% base workspace and Command Window.
%
% SYNTAX
% 1) SEGMENTIMAGE
%       If segmentImage App exists, brings it to the front; otherwise,
%       creates a segmentImage App with a default image. New images can be
%       imported, from file or from workspace variables.
%
% 2) SEGMENTIMAGE(IMG)
%       Creates a segmentImage App, pre-loaded with the image in IMG. (See
%       NOTE on "singleton" below.)
%
% 3) SEGMENTIMAGE(IMG,MAP)
%       Also loads colormap MAP.
%
% 4) SEGMENTIMAGE(IMG,MAP,PARENT)
%       Creates segmentImage as a child of PARENT. (DEFAULT behavior is a
%       new figure.) Note that MAP may be empty.
%
% NOTES: Note that segmentImage is "singleton" by design; you can't have
%        multiple instances open simultaneously. You can change that
%        behavior by changing "singleton" to false at line 60.
%
%        All images are converted to type 'double' for processing.
%
%        In many cases, tooltipstrings guide the user. In others,
%        functionality is thought to be self-explanatory and
%        self-discoverable. When in doubt about the usage of some function
%        parameters, simply try them out or read the documentation for the
%        function.
%
%        In acknowledgement of the fact that tooltipstrings and
%        notification sounds can get annoying, I have implemented menu
%        items (under OPTIONS) to toggle them on/off. (They are both "on"
%        by default.)
%
%        CURRENT TAB PANELS:
%             EDGE, THRESHOLDING, HOUGH LINE/CIRCLE, and
%             REGIONAL/EXTENDED MIN/MAX, COLOR-BASED, TEXTURE-BASED.
%
%        Thanks to Simone Haemmerle (my colleague in the German MathWorks
%        office) for her suggestions.
%
%        Comments, suggestions welcome!
%
% See also: imageMorphology, StrelTool


% Written by Brett Shoelson, PhD
% brett.shoelson@mathworks.com
%
% UPDATES:
% 11/01/12: Included color segmentation tab/functionality.
% 4/28/14:  Fixed typos; now indicate when color-based maps don't change
%           with slider movement.
% 5/30/14:  General cleanup; preparation for R2014b readiness.
% 11/17/14: Significant cleanup; modified name from SegmentTool to
%           segmentImage (and Segment Image app). Changed slider operation
%           of threshold panel; incorporated multithresh; deprecated manual
%           color selection tab (link instead to colorThresholder).
%
% Copyright 2010-2014 The MathWorks, Inc.

narginchk(0,3);
tmp = findall(groot,'name','Segment Image');
singleton = true;

if ~nargin
	if ~isempty(tmp)
		figure(tmp)
		return
	end
else
	if singleton
		delete(findall(groot,'name','Segment Image')); %Singleton
	end
end

% INITIALIZATIONS/DEFAULTS:
segtool = [];
requestedPanels = {{'Edge','Thresholding','Hough Line/Circle'},...
	{'Regional/Extended Min/Max','Color-Based'}};

original.fname = 'Original';

if nargin > 0
	% nargin > 0
	validateattributes(varargin{1},{'numeric','char','logical'},{'nonempty'})
	original.img = varargin{1};
	% nargin > 1
	if nargin > 1 % COLORMAP specified
		original.cmap = varargin{2};
	end
	if ischar(original.img)
		try
			original.fname = original.img;
			[original.img,original.cmap] = imread(original.img);
		catch
			error('SEGMENTIMAGE: Unable to read specified image.');
		end
	end
	
	% nargin > 2
	if nargin > 2 % PARENT specified
		iptcheckinput(varargin{3}, {'double'}, {''},...
			mfilename, 'segtool', 3);
		segtool = varargin{3};
		if ~ishandle(segtool)
			error('Third argument must be a single handle for the parent of the segtool.');
		end
	end
else
	original.img = imread('peppers.png');
	original.cmap = [];
	original.fname = 'Original';
end

%Share in main workspace
[allTooltips,autoSens,...
	autoSigma,colorMaskAxHandles,colorMaskPanel,...
	contractionBias,edgeDir,edgeType,extDir,extType,graythreshVal,...
	histax,houghAx,houghLinesOpts,...
	houghPeakOpts,hSldr,lastCommand,localThresh,...
	multithreshIndexButtons,nColors,nColorsSldr,nConn,nConnOpts,nConnValue,notification,...
	nThresholds,numPeaks,quantIndex,quantizedImg,rgbIndices,rhoRes,...
	sensEdt,sensSldr,...
	sigmaEdt,sigmaSldr,...
	thetaMax,thetaMin,thetaRes,threshLine,threshVal,threshvalIndicator,...
	titleHandles,usingGray] = deal([]);

[wav,freq] = audioread('notify.wav');
notification = audioplayer(wav,freq);

colors = bone(30);
colors = colors(14:end,:);
bgc = colors(4,:);
% colors = min(1,bone(30)*1.3);
% colors = colors(14:end,:);
% bgc = colors(4,:)/1.4;

if isempty(segtool)
	segtool = figure(...
		'numbertitle', 'off',...
		'WindowStyle','normal',...
		'name', 'Segment Image',...
		'units', 'pixels',...
		'color', bgc,...
		'position', ceil(get(groot,'screensize') .* [1 1 0.975 0.875]),...
		'menubar', 'none',...
		'toolbar','none',...
		'visible','off');
end
segtoolHandle = segtool;
set(segtool,'visible','off');
if isrgb(original.img)
	%DEFAULT grayversion
	original.grayversion = rgb2gray(original.img);
else
	original.grayversion = original.img;
end

% WORK WITH ALL IMAGES AS TYPE DOUBLE
if ~islogical(original.img)
	original.img = im2double(original.img);
	original.segmented = [];
else
	original.segmented = original.img;
end
original.grayversion = im2double(original.grayversion);

% UIMENUS
parentFigure = ancestor(segtool,'figure');

f = uimenu(parentFigure,'Label','FILE');
uimenu(f,'Label','Import','callback',@getFile);
uimenu(f,'Label','Commit current working image','callback',{@convertImage,'CurrentWorkingImage'});
uimenu(f,'Label','Export Segmented','callback',@exportBW);
f = uimenu(parentFigure,'Label','CONVERSIONS');
tmp = uimenu(f,'Label','...to Grayscale');
uimenu(tmp,'Label','RGB2Gray','callback',{@convertImage,'RGB2gray'});
uimenu(tmp,'Label','Select Gray Image','callback',{@convertImage,'grayscale'});
uimenu(f,'Label','...to HSV','callback',{@convertImage,'HSV'});
uimenu(f,'Label','...to L*A*B*','callback',{@convertImage,'LAB'});
uimenu(f,'Label','...Decorrelation Stretch','callback',{@convertImage,'Decorrstretch'});
uimenu(f,'Label','Complement Image','callback',{@convertImage,'Complement'});
f = uimenu(parentFigure,'Label','MODIFY MASK');
uimenu(f,'Label','Reverse Mask','callback',@reverseMask);
uimenu(f,'Label','Export Mask','callback',@exportBW);

f = uimenu(parentFigure,'Label','OPTIONS');
uimenu(f,'Label','Verify Destructive Commands','checked','on',...
	'tag','Verify','callback',@toggleMenuItem);
uimenu(f,'Label','Disable Tooltips','checked','off',...
	'tag','DisableTooltips','callback',@toggleMenuItem);
uimenu(f,'Label','Turn sounds off','checked','on',...
	'tag','TurnOffSounds','callback',@toggleMenuItem);

% CREATE MAIN FIGURE
if strcmp(get(segtool,'type'),'figure')
	centerfig(segtool);
end
% Default units
tmp = get(0,'screensize');
if tmp(3) > 1200
	defaultFontsize = 8;
else
	defaultFontsize = 7;
end
set(segtool,'DefaultUicontrolUnits','normalized',...
	'DefaultUicontrolFontSize',defaultFontsize);

annotation('textbox',[0.015 0.96 0.565 0.0275],...
	'string','CLICK ON ANY IMAGE TO VIEW IT IN A LARGER WINDOW.',...
	'color', [0.043137 0.51765 0.78039]*0.8,...
	'horizontalalignment','c','fontweight','b','fontsize',8,...
	'verticalalignment','m',...
	'backgroundcolor',bgc*1.3);
% CREATE MAIN IMAGE PANEL
% CREATE IMAGE AXES
origax = axes('parent',segtool,'pos', [0.1 0.1 0.1 0.1],'visible','off');%TEMPORARY...for setup
cla
imshow(original.img);
% overlayax = axes('parent',segtool,'pos',[0.24 0.02 0.2 0.25],'visible','off');
workingax = axes('parent',segtool,...
	'pos', [0.1 0.1 0.1 0.1],...
	'visible','off');%TEMPORARY...for setup

% OVERLAY PANEL
overlayColor = [1 0 0];
overlayPanel = uipanel('parent',segtool,...
	'position',[0.26 0.02 0.32 0.25],...
	'bordertype','etchedin','title','Segmentation-Visualization Tools',...
	'backgroundcolor',colors(4,:));
overlayax = axes('parent',overlayPanel,'pos',[0.1 0.1 0.1 0.1],'visible','off');%TEMPORARY...for setup
overlayColorButton = uicontrol(overlayPanel,'style','pushbutton',...
	'pos',[0.635 0.8 0.0725 0.15],...
	'backgroundcolor',overlayColor,...
	'callback',@changeOverlayColor,...
	'tooltipstr','Change the color of the segmentation-mask overlay.');
%'cdata',reshape(kron(overlayColor,ones(18,18)),18,18,3),...
setappdata(overlayColorButton,'overlayColor',overlayColor);
uicontrol(overlayPanel,'style','text','string',{'Overlay';'Color'},...
	'position',[0.72 0.72 0.1 0.25],'backgroundcolor',bgc,...
	'horizontalalignment','l',...
	'tooltipstr','Change the color of the segmentation-mask overlay.');
%[0.635 0.8 0.0725 0.15]
uicontrol(overlayPanel,'style','pushbutton','pos',[0.835 0.8 0.15 0.15],...
	'string','Flip Stack','callback',@flipImages,...
	'tooltipstr','Reverse the stacking order of the image and the current overlay (for visualization of segmentation-mask alignment).');
[a,b] = distributeObjects(2,0.05,0.775,0.015);
[imgOpacitySldr,~,~] = ...
	sliderPanel(overlayPanel,...
	{'backgroundcolor',bgc,'title','Image Opacity','pos',[0.635 a(1) 0.35 b],...
	'units','normalized','fontsize',defaultFontsize-1},...
	{'backgroundcolor',colors(5,:),'min',0,'max',1,'value',1,...
	'callback',{@modifyOpacity,2},'sliderstep',[0.01 0.1],...
	'tooltipstring',sprintf('Modify the transparency of the image.\nRight-Click bar to reset to default.')},...
	{'backgroundcolor',colors(5,:),'fontsize',defaultFontsize-1},...
	{'backgroundcolor',bgc,'fontsize',defaultFontsize-1},...
	'%0.2f');
[overlayOpacitySldr,~,~] = ...
	sliderPanel(overlayPanel,...
	{'backgroundcolor',bgc,'title','Overlay Opacity','pos',[0.635 a(2) 0.35 b],...
	'units','normalized','fontsize',defaultFontsize-1},...
	{'backgroundcolor',colors(5,:),'min',0,'max',1,'value',0.4,...
	'callback',{@modifyOpacity,1},'sliderstep',[0.01 0.1],...
	'tooltipstring',sprintf('Modify the transparency of the overlay.\nRight-Click bar to reset to default.')},...
	{'backgroundcolor',colors(5,:),'fontsize',defaultFontsize-1},...
	{'backgroundcolor',bgc,'fontsize',defaultFontsize-1},...
	'%0.2f');

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% MAIN PANELS: SEGMENTATION
% Create Working TabPanels
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
del = 0.1;
[~,mainTabCardHandles,mainTabHandles] = ...
	tabPanel(segtool,requestedPanels,...
	'panelpos',[0.60 0.12+del-0.05 0.38 0.8175],...[0.015 0.96 0.565 0.0275]
	'tabpos','t',...
	'colors',colors,...
	'tabHeight',35,...
	'highlightColor','w',...'c'
	'tabCardPVs',{'bordertype','etchedin','fontsize',defaultFontsize},...
	'tabLabelPVs',{'fontsize',defaultFontsize,'foregroundcolor',[0.043 0.52 0.78]*0.5});
requestedPanels = {{'Edge','Thresholding','Hough Line/Circle'},...
	{'Regional/Extended Min/Max','Color-Based'}};
% EDGE:
set(mainTabHandles{1}(1),'tooltipstring','Find edges in a grayscale image using any of the 6 algorithms in the Image Processing Toolbox.');
% THRESHOLDING
set(mainTabHandles{1}(2),'tooltipstring','Interactively apply global or blockwise threshold values.');
% HOUGH LINE/CIRCLE
set(mainTabHandles{1}(3),'tooltipstring','Detect lines or circles in the working image.');
% REGIONAL/EXTENDED MIN/MAX
set(mainTabHandles{2}(1),'tooltipstring','Detect extended and regional minima and maxima.');
% COLOR-BASED
set(mainTabHandles{2}(2),'tooltipstring','Use color information to segment image.');

setappdata(segtool,'mainTabCardHandles',mainTabCardHandles);
setappdata(segtool,'mainTabHandles',mainTabHandles);
tmp = get(mainTabCardHandles{1}(1),'units');
set(mainTabCardHandles{1}(1),'units','characters');
stringWidth = get(mainTabCardHandles{1}(1),'pos');
stringWidth = floor(stringWidth(3)*0.7);
set(mainTabCardHandles{1}(1),'units',tmp);

[objpos,objdim] = distributeObjects(2,0.6,0.98,0.01);
%resetButton = ...
uicontrol(segtool,'style','pushbutton',...
	'pos',[objpos(1) 0.125 objdim 0.0375],...
	'string','Reset to Original','callback',@reset,...
	'tooltipstring','Reset working image to original image (or image "committed" via File Menu.');
%exportButton = ...
uicontrol(segtool,'style','pushbutton',...
	'pos',[objpos(2) 0.125 objdim 0.0375],...
	'string','Export Image and Generate Code','callback',@exportBW,...
	'tooltipstring',sprintf('Write image to base workspace (naming is automatic)\nand show reproduction steps (code) in Command Window.'));
commentPanel = uipanel(segtool,'bordertype','etchedin','title','COMMENTS',...
	'backgroundcolor',bgc,...
	'position',[0.6 0.02 0.38 0.0975]);
commentBox = uicontrol(commentPanel,'style','listbox',...
	'position',[0.05 0.025 0.9 0.95],'backgroundcolor',bgc,...
	'foregroundcolor','k','fontsize',defaultFontsize+1,'max',10,'min',1,...
	'horizontalalignment','l','string',[]);
throwComment(sprintf('Original Image is %0.0f x %0.0f x %0.0f, class %s',size(original.img,1),size(original.img,2),size(original.img,3), class(original.img)));

if ~isempty(original.img)
	updateWorkingImg(original.img,[],original.fname,1)
end

[objpos,objdim] = distributeObjects(3,0.05,0.95,0.01);
if iscell(requestedPanels{1})
	for tier = 1:size(requestedPanels,2)
		for rank = 1:numel(requestedPanels{tier})
			setupPanel(requestedPanels{tier}(rank),tier,rank);
		end
	end
else
	tier = 1;
	for rank = 1:numel(requestedPanels)
		setupPanel(requestedPanels(rank),tier,rank)
	end
end

% SET ALL CALLBACKS AND BUSYACTIONS
hndls = [autoSens,autoSigma,edgeType,edgeDir,extType,...
	extDir,nConnValue,houghPeakOpts,houghLinesOpts];
%DEFAULT CALLS TO PROCESSREQUEST (no inputs)
for jj = 1:numel(hndls)
	iptaddcallback(hndls(jj),'callback',@processRequest);
end %Add processRequest as callback
set(hndls,'BusyAction','cancel');
set(segtool,'visible','on');
set(parentFigure,'handlevisibility','callback')
if nargout < 1
	clear segtoolHandle
end
% BEGIN NESTED SUBFUNCTIONS

	function overlayColor = changeOverlayColor(varargin)
		overlayColor = getappdata(overlayColorButton,'overlayColor');
		overlayColor = uisetcolor(overlayColor);
		%set(overlayColorButton,'cdata',reshape(kron(overlayColor,ones(15,15)),15,15,3));
		set(overlayColorButton,'backgroundcolor',overlayColor);
		setappdata(overlayColorButton,'overlayColor',overlayColor);
		set(parentFigure,'CurrentAxes',overlayax);
		img = get(imhandles(workingax),'cdata');
		if islogical(img)
			updateOverlay(img);
		else
			currOverlay = findall(gcf,'tag','opaqueOverlay');
			if ~isempty(currOverlay)
				updateOverlay(any(currOverlay.CData,3));
			end
		end
	end %changeOverlayColor

	function clearAutoBlocksize(varargin)
		set(findobj('tag','autoSelectBlocksize'),'value',0);
	end %clearAutoBlocksize

	function convertImage(varargin)
		successMsg = 'Update Successful.';
		verify = get(findobj(segtool,'tag','Verify'),'checked');
		tmp = 'CONTINUE';
		switch varargin{3}
			case 'CurrentWorkingImage'
				% COMMIT
				if strcmp(verify,'on')
					tmp = questdlg(sprintf('This modifies the original image; are you sure you want to continue?\n\n(Turn off ''Verify Destructive Commands'' in the Options Menu to suppress this warning.)'),'Continue?','CONTINUE','Cancel','CONTINUE');
				else
					tmp = 'CONTINUE';
				end
				if ~strcmp(tmp,'CONTINUE')
					return
				end
				updateWorkingImg(get(imhandles(workingax),'cdata'),[],'Original',1);
				throwComment(successMsg,0,1);
			case 'double'
				updateWorkingImg(original.img,[],original.fname,1);
				throwComment(successMsg,0,1);
			case 'RGB2gray'
				if ~isempty(original.cmap)
					updateWorkingImg(ind2gray(original.img,cmap),[],original.fname,0);
					throwComment(successMsg,0,1);
					throwComment('To continue working with this modified image, you may "Commit" it using FILE->COMMIT, if you so desire.',1,1);
				elseif isrgb(original.img)
					updateWorkingImg(rgb2gray(original.img),[],original.fname,0);
					throwComment(successMsg,0,1);
					throwComment('To continue working with this modified image, you may "Commit" it using FILE->COMMIT, if you so desire.',1,1);
				else
					throwComment('Invalid conversion for original image.',1,1);
				end
			case 'grayscale'
				if ~isrgb(original.img)
					throwComment('Conversion valid only for RGB original',1,1);
					return
				else
					figure('numbertitle','off','name','Temporary','tag','tmpfig','windowstyle','normal');
					ax(1) = subplot(2,2,1);
					imshow(rgb2gray(original.img));
					title('IM2GRAY');
					ax(2) = subplot(2,2,2);
					imshow(original.img(:,:,1));
					title('RED Plane')
					ax(3) = subplot(2,2,3);
					imshow(original.img(:,:,2));
					title('GREEN Plane')
					ax(4) = subplot(2,2,4);
					imshow(original.img(:,:,3));
					title('BLUE Plane')
					set(ax,'units','normalized')
					a = get(ax,'position');
					for ii = 1:4
						tmp = a{ii};
						uicontrol('style','radio','units','normalized','pos',[tmp(1) tmp(2)*0.9 tmp(3) 0.05],...
							'string','Use this image','value',0,'callback',{@useThisImage,ii});
					end
					return
				end
			case {'RedPlane','GreenPlane','BluePlane'}
				if size(original.img,3) < 3
					throwComment('Invalid conversion for original image',1,1);
				else
					updateWorkingImg(original.img(:,:,strcmp(varargin{3},{'RedPlane','GreenPlane','BluePlane'})),[],original.fname,0);
					throwComment(successMsg,0,1);
					throwComment('To continue working with this modified image, you may "Commit" it using FILE->COMMIT, if you so desire.',1,1);
				end
			case 'HSV'
				if isrgb(original.img)
					updateWorkingImg(rgb2hsv(original.img),[],original.fname,0);
					throwComment('To continue working with this modified image, you may "Commit" it using FILE->COMMIT, if you so desire.',1,1);
				else
					throwComment('Conversion valid only for RGB original',1,1);
				end
			case 'LAB'
				if isrgb(original.img)
					cform = makecform('srgb2lab');
					updateWorkingImg(applycform(original.img,cform),[],original.fname,0);
					throwComment(successMsg,0,1);
					throwComment('To continue working with this modified image, you may "Commit" it using FILE->COMMIT, if you so desire.',1,1);
				else
					throwComment('Conversion valid only for RGB original',1);
				end
			case 'Decorrstretch'
				if isrgb(original.img)
					updateWorkingImg(decorrstretch(original.img),[],original.fname,0);
					throwComment(successMsg,0,1);
					throwComment('To continue working with this modified image, you may "Commit" it using FILE->COMMIT, if you so desire.',1,1);
				else
					throwComment('Conversion valid only for RGB original',1,1);
				end
			case 'Complement'
				updateWorkingImg(imcomplement(original.img),[],original.fname,0);
				throwComment(successMsg,0,1);
				throwComment('To continue working with this modified image, you may "Commit" it using FILE->COMMIT, if you so desire.',1,1);
		end
	end %convertImage

	function exportBW(varargin)
		img = get(imhandles(workingax),'cdata');
		%         if ~islogical(img)
		%             throwComment('It appears that you haven''t segmented the image yet!',1,1);
		%             return
		%         end
		n = 0; tmp = 1;
		while tmp
			n = n + 1;
			tmp = evalin('base',['exist(''segtoolimage', num2str(n), ''')']);
		end
		throwComment(sprintf('Current image written to segtoolimage%d, and reproduction steps written to Command Window.\n',n),1,1);
		fprintf('\nCurrent image written to segtoolimage%d\n',n)
		assignin('base',['segtoolimage' num2str(n)],img);
		fprintf('\nREPRODUCTION STEPS:\n******************\n')
		disp(char(lastCommand))
		fprintf('******************\n')
		fprintf('(NOTE that non-double images are\nconverted to type  ''double'' in segmentImage;\nthese commands reflect operations on images\nthat may have been converted with ''IM2DOUBLE''.)\n\n');
	end %exportBW

	function flipImages(varargin)
		set(overlayax,'children',flipud(get(overlayax,'children')));
	end %flipImages

	function img = getFile(varargin)
		[img,cmap,original.fname,~,userCanceled] = getNewImage(true);
		if userCanceled
			return
		end
		lastCommand = '';
		if isrgb(img)
			original.grayversion = rgb2gray(img);
		else
			original.grayversion = img;
		end
		original.img = img;
		if ~islogical(original.img)
			original.img = im2double(original.img);
			original.segmented = [];
		else
			original.segmented = original.img;
		end
		original.grayversion = im2double(original.grayversion);
		
		isImageTypeIndexed = ~isempty(original.cmap);
		if isImageTypeIndexed
			if isempty(map_var_name)
				% user is importing an indexed image, but did not select a
				% colormap. USE DEFAULT.
			else
				original.cmap = evalin('base',map_var_name);
				img = ind2rgb(img,original.cmap);
			end
		end
		updateWorkingImg(img,cmap,original.fname,1);
	end %getFile

	function img = imSelected(varargin)
		currColor = get(gcbo,'backgroundcolor');
		if all(currColor == [1 0 0])
			set(gcbo,'backgroundcolor','g');
		else
			set(gcbo,'backgroundcolor','r');
		end
		inclusions = [];
		for kk = 1:nColors
			tmp = get(titleHandles(kk),'backgroundcolor');
			if all(tmp == [0 1 0])
				inclusions = [inclusions,get(titleHandles(kk),'userdata')]; %#ok
			end
		end
		img = ismember(rgbIndices,inclusions);
		updateWorkingImg(img);
		updateOverlay(img);
		throwComment('Ready',0,1);
		lastCommand = {sprintf('rgbIndices = rgb2ind(img,%0.0f);',nColors);
			sprintf('mask = ismember(rgbIndices,[%s]);',num2str(inclusions))};
		togglePointer('arrow');
	end %imSelected

	function pass = isrgb(test)
		s = size(test);
		pass = length(s) == 3 && s(3) == 3 && ~islogical(test);
	end %isrgb

	function modifyOpacity(varargin)
		set(parentFigure,'CurrentAxes',overlayax);
		switch varargin{3}
			case 1 %Modify overlay opacity
				currOverlay = findall(gcf,'tag','opaqueOverlay');
				% 				overlayColor = getappdata(overlayColorButton,'overlayColor');
				% 				opacity = get(overlayOpacitySldr,'value');
				if ~isempty(currOverlay)
					%showMaskAsOverlay(opacity,any(currOverlay.CData,3),overlayColor,overlayax);
					updateOverlay(any(currOverlay.CData,3));
				end
			case 2 %Modify image opacity
				set(original.overlayImgHndl,...
					'alphadata',get(imgOpacitySldr,'value'));
		end
	end %modifyOpacity

	function LaunchCircleFinder(varargin)
		if exist('circleFinder','file')
			circleFinder(get(imhandles(workingax),'cdata'))
		else
			throwComment('Please ensure that you are using MATLAB R2012a or later, and ...',1,1);
			throwComment('      ... download and install circleFinder from the MATLAB Central File Exchange!',0,1);
		end
	end %LaunchCircleFinder

	function processRequest(varargin)
		% Main Switchyard to manage callback requests.
		% Called with one or three inputs.
		% If one argument, the input is the handle to the Callback Object,
		% and the type of the requested segmentation is automatically
		% determined by the name of the active panel. If multiple inputs
		% are passed, varargin{3} should be the name of the requested
		% segmentation type. (e.g., {@processRequest,'Edge'})).
		%
		% The multiple-argument form of this function allows multiple
		% segmentation types to be captured in a single panel.
		
		togglePointer('watch');
		%throwComment('Working...')
		requestingObject = varargin{1};
		reqObjTag = get(requestingObject,'tag');
		allHandles = cell2mat(mainTabCardHandles');
		usePanel = find(strcmp(get(allHandles,'visible'),'on'));
		if nargin < 3
			segType = get(allHandles(usePanel),'Title');%#ok
		else
			segType = varargin{3};
		end
		
		optionalInputs = [];
		% Specific actions prior to segmentation
		switch reqObjTag %Alphabetical listing
			case 'ActiveContour'
				segType = 'ActiveContour';
				%set(gcf,'pointer','arrow');return
			case 'calcColorMasks'
				segType = 'calcColorMasks';
				img = original.img;
				if ~isrgb(img)
					throwComment('This option is available only for RGB images!',1,1);
					set(gcf,'pointer','arrow');
					return
				end
				updateWorkingImg(img);
				updateOverlay([]);
			case 'HoughPeakThresh'
				newVal = str2double(get(requestingObject,'string'));
				if isempty(newVal) || isnan(newVal) || newVal < 0
					newVal = 0.5*max(original.img(:)); %Default
				end
				set(requestingObject,'string',sprintf('%0.3f',newVal));
			case {'HoughNHoodSize1','HoughNHoodSize2'}
				%dim = find(strcmp(reqObjTag,{'HoughNHoodSize1','HoughNHoodSize2'}));
				%maxsize = size(original.img,dim);
				newVal = floor(str2double(get(requestingObject,'string')));
				if isempty(newVal) || isnan(newVal) || newVal < 0 %|| newVal >= maxsize
					newVal = size(original.img)/50;
					newVal = max(2*ceil(newVal/2) + 1, 1); % Make sure the nhood size is odd; % Default
					newVal = newVal(strcmp(reqObjTag,{'HoughNHoodSize1','HoughNHoodSize2'}));
				end
				set(requestingObject,'string',sprintf('%0.0f',newVal));
			case 'HoughLinesFillGap'
				newVal = str2double(get(requestingObject,'string'));
				if isempty(newVal) || isnan(newVal) || newVal < 0 || isinf(newVal)
					newVal = 20;
				end
				set(requestingObject,'string',newVal);%sprintf('%0.0f',newVal));
			case 'HoughLinesMinLength'
				newVal = str2double(get(requestingObject,'string'));
				if isempty(newVal) || isnan(newVal) || newVal < 0 || isinf(newVal)
					newVal = 40;
				end
				set(requestingObject,'string',newVal);%sprintf('%0.0f',newVal));
			case 'launchColorThresholder'
				if ~isrgb(original.img)
					throwComment('This option is only valid for RGB images.',1,1);
					set(gcf,'pointer','arrow');
					return
				end
				oldws = get(groot,'defaultfigurewindowstyle');
				set(groot,'defaultfigurewindowstyle','normal');
				set(gcf,'pointer','arrow');
				drawnow;
				colorThresholder(original.img);
				set(groot,'defaultfigurewindowstyle',oldws);
				return			
			case 'LocalOtsuThresholding'
				optionalInputs = varargin{4};
			case 'multithreshSldr'
				nThresholds = round(get(requestingObject,'value'));
				segType = 'multithresh';
			case 'SensSldr'
				set(autoSens,'value',0);
			case 'SigmaSldr'
				set(autoSigma,'value',0);
			case 'threshLine'
				threshVal = threshLine.XData(1);
		end
		% Create segmentation mask
		segmented = segment(segType,optionalInputs);
		if islogical(segmented)
			updateOverlay(segmented);
			original.segmented = segmented;
		end
	end %processRequest

	function refreshHistax(parent)
		histax = axes('parent',parent,'units','normalized',...
			'pos',[0.1 0.695 0.85 0.2],...
			'fontsize',6);
		imhist(original.grayversion);
		hold on;
		threshVal = graythresh(original.grayversion);
		graythreshVal = threshVal;
		title(sprintf('DRAG RED LINE TO THRESHOLD;\nRIGHT-CLICK TO RESET (Graythresh/Auto-thresh = %0.2f)',threshVal),...
			'color',[0.043 0.52 0.78]*0.5,...
			'fontweight','bold',...
			'fontsize',8.5);
		line([threshVal, threshVal],ylim,...
			'color',[0.4 0.4 0.4],...
			'linewidth',1,...
			'linestyle','--',...
			'tag','threshLine');
		threshLine = line([threshVal, threshVal],ylim,...
			'color','r',...
			'linewidth',2,...
			'tag','threshLine');
		tmp = get(histax,'position');
		threshvalIndicator = uicontrol(parent,...
			'position',[tmp(1)+tmp(3)-0.08 tmp(2)+tmp(4)-0.05 0.06 0.04],...
			'string',num2str(graythreshVal,2),...
			'tag','threshvalIndicator',...
			'fontsize',9,...
			'horizontalalignment','right',...
			'fontweight','bold',...
			'style','text',...
			'backgroundcolor','w',...
			'foregroundcolor','r',...
			'enable','inactive');
		set(histax,'fontsize',8)
		set(threshLine,'LineWidth',2,'UserData',threshVal)
		draggableBrief(threshLine,@processRequest)
		set(setdiff(findall(gca),threshLine),'buttondownfcn',@resetGraythreshVal);
	end %refreshHistax

	function reset(varargin)
		% WRAPPER for verification of destructive command
		verify = get(findobj(segtool,'tag','Verify'),'checked');
		if strcmp(verify,'on')
			tmp = questdlg(sprintf('This operates on the original image; any interim results will be lost.\n(You may want to save/export your results first.)\n\n(Turn off ''Verify Destructive Commands'' in the Options Menu to suppress this warning.)'),'Continue?','CONTINUE','Cancel','CONTINUE');
		else
			tmp = 'CONTINUE';
		end
		if strcmp(tmp,'CONTINUE')
			updateWorkingImg(original.img,original.cmap,original.fname,1);
			updateOverlay([]);
		end
		throwComment('Ready');
	end %reset

	function resetGraythreshVal(varargin)
		if strcmp(get(gcf,'selectiontype'),'alt')
			set(threshLine,'xdata',[graythreshVal graythreshVal]);
			set(threshvalIndicator,'string',num2str(graythreshVal,2))
			processRequest(threshLine)
		end
	end %resetGraythreshVal

	function reverseMask(varargin)
		img = get(imhandles(workingax),'cdata');
		if ~islogical(img)
			throwComment('There does not appear to be a valid binary image in the working axis!',1,1);
			return
		else
			img = ~img;
			throwComment('Mask reversed.',0,1);
			updateWorkingImg(img);
			updateOverlay(img);
		end
	end %reverseMask

	function img = segment(segType,varargin)
		% THE WORKHORSE
		% USE ORIGINAL;
		usingGray = false;
		% Some processes return non-binary images
		if ismember(segType,{'Hough Line/Circle'})%,'Thresholding'
			if ~isempty(original.segmented)
				img = original.segmented;
			else
				img = get(imhandles(workingax),'cdata');
			end
		else
			img = original.img;
		end
		uwi = 1; % Flag: update working image
		switch segType
		case 'Edge'
				if isrgb(img)
					usingGray = true;
					img = original.grayversion;
				end
				ind = find(cell2mat(get(edgeType,'value')));
				requestedEdge = get(edgeType(ind),'string');%#ok
				useAutoSens = get(autoSens,'value');
				if useAutoSens
					thresh = [];
				else
					thresh = get(sensSldr,'value');
				end
				switch requestedEdge
					case {'Sobel','Prewitt'}
						ind = find(cell2mat(get(edgeDir,'value')));
						requestedDir = get(edgeDir(ind),'string');%#ok
						[img,threshOut] = edge(img,requestedEdge,thresh,requestedDir);
						lastCommand = sprintf('[img,threshOut] = edge(img,''%s'',[%0.2f],''%s'');',requestedEdge,thresh,requestedDir);
						throwComment(sprintf('Searching for edges in [the] %s direction[s]',requestedDir),0,1);
					case 'Roberts'
						[img,threshOut] = edge(img,requestedEdge,thresh);
						lastCommand = sprintf('[img,threshOut] = edge(img,''%s'',%0.2f);',requestedEdge,thresh);
					case {'LOG','Canny'}
						useAutoSigma = get(autoSigma,'value');
						if useAutoSigma
							if strcmp(requestedEdge,'LOG')
								sigma = 2; %Default
							else
								sigma = 1; %Default
							end
							set(sigmaEdt,'string',num2str(sigma));
							set(sigmaSldr,'value',sigma);
						else
							sigma = max(0.001,get(sigmaSldr,'value'));
						end
						[img,threshOut] = edge(img,requestedEdge,thresh,sigma);
						if isempty(thresh)
							thresh = '[]';
						else
							thresh = num2str(thresh);
						end
						lastCommand = sprintf('[img,threshOut] = edge(img,''%s'',%s,%0.2f);',requestedEdge,thresh,sigma);
					case 'ZeroCross'
						[img,threshOut] = edge(img,requestedEdge,thresh);
						if isempty(thresh)
							lastCommand = sprintf('[img,threshOut] = edge(img,''%s'');',requestedEdge);
						else
							lastCommand = sprintf('[img,threshOut] = edge(img,''%s'',%0.2f);',requestedEdge,thresh);
						end
				end
				if useAutoSens
					if numel(threshOut) > 1
						threshOut = threshOut(2);
						% See note on Canny
					end
					set(sensEdt,'string',sprintf('%0.3f',threshOut));
					set(sensSldr,'value',threshOut);
				end
				throwComment([requestedEdge ' Edge Detection']);
			case 'Thresholding'
				if isrgb(img)
					usingGray = true;
					img = original.grayversion;
				end
				throwComment('THRESHOLDING',0,1);
				img = img > threshVal;
				if isequal(threshVal,graythreshVal)
					lastCommand = sprintf('img = img > %0.2f;\nOR\nimg = im2bw(img,%0.2f);\nOR\nimg = im2bw(img,graythresh(img));',threshVal,threshVal);
				else
					lastCommand = sprintf('img = img > %0.2f;\nOR\nimg = im2bw(img,%0.2f);',threshVal,threshVal);
				end
			case 'multithresh'
				if isrgb(img)
					usingGray = true;
					img = original.grayversion;
				end
				throwComment('QUANTIZING',0,1);
				thresholds = multithresh(img,nThresholds);
				[quantizedImg,quantIndex] = imquantize(img,thresholds);
				set(multithreshIndexButtons,'string','X');
				quantizedImg = label2rgb(quantizedImg);
				updateWorkingImg(quantizedImg);
				set(multithreshIndexButtons,'visible','off');
				set(multithreshIndexButtons(1:nThresholds+1),'visible','on');
				for ii = 1:nThresholds+1
					[r,c] = ind2sub(size(quantizedImg),find(quantIndex==ii,1,'first'));
					set(multithreshIndexButtons(ii),...
						'backgroundcolor',quantizedImg(r,c,:));
				end
				updateOverlay([]);
				uwi = false;
			case 'Hough Line/Circle'
				if ~islogical(img)
					throwComment('Hough functions operate on binary image; consider using edge detection routine before continuing.',1);
					togglePointer('arrow');
					return
				else
					thetaResVal = min(90-1e-1,max(1e-1,get(thetaRes,'value')));
					rhoResVal = get(rhoRes,'value');
					if get(rhoRes,'value') > norm(size(img))
						throwComment('rhoRes auto-limited to norm(size(img))',1,1);
						rhoResVal = min(norm(size(img))-1e-1,max(1e-1,get(rhoRes,'value')));
					end
					minTheta = get(thetaMin,'value');
					maxTheta = get(thetaMax,'value');
					if minTheta >= maxTheta
						throwComment('Waiting for valid theta range (minTheta < maxTheta)',0,1);
						togglePointer('arrow');
						return
					end
					numPeaksVal = round(get(numPeaks,'value'));
					houghPeakThresh = str2double(get(houghPeakOpts(1),'string'));
					houghNHoodSize1 = str2double(get(houghPeakOpts(2),'string'));
					houghNHoodSize2 = str2double(get(houghPeakOpts(3),'string'));
					houghLinesFillGap = str2double(get(houghLinesOpts(1),'string'));
					houghLinesMinLength = str2double(get(houghLinesOpts(2),'string'));
					
					if maxTheta >=90
						maxTheta = 90-thetaResVal;
					end
					[H,T,R] = hough(img,'Theta',minTheta:thetaResVal:maxTheta,...
						'RhoResolution',rhoResVal);
					%toc
					if any([houghNHoodSize1 >= size(H,1),houghNHoodSize2 >= size(H,2),~isodd(houghNHoodSize1),~isodd(houghNHoodSize2)])
						houghNHoodSize1 = min(houghNHoodSize1,size(H,1)-1);
						if ~isodd(houghNHoodSize1)
							houghNHoodSize1 = max(2*ceil(houghNHoodSize1/2) - 1, 1); % Make sure the nhood size is odd
						end
						houghNHoodSize2 = max(1,min(houghNHoodSize2,size(H,2)-1));
						if ~isodd(houghNHoodSize2)
							houghNHoodSize2 = max(2*ceil(houghNHoodSize2/2) - 1, 1); % Make sure the nhood size is odd
						end
						set(houghPeakOpts(2),'string',houghNHoodSize1);
						set(houghPeakOpts(3),'string',houghNHoodSize2);
						throwComment('Using nearest valid value of neighborhood size. (See Help for HOUGHPEAKS.)',0,1);
					end
					
					P  = houghpeaks(H,numPeaksVal,...
						'threshold',houghPeakThresh,...
						'NHoodSize',[houghNHoodSize1 houghNHoodSize2]);
					% display the hough matrix
					axes(houghAx);
					cla;
					imshow(imadjust(mat2gray(H)),'XData',T,'YData',R,'InitialMagnification','fit');
					xlabel('\theta'), ylabel('\rho');
					axis on, axis normal, hold on;
					xlim([minTheta,maxTheta])
					lines = [];
					if ~isempty(P)
						% 						home
						% 						clusters = clusterData(T(P(:,2)))
						plot(T(P(:,2)),R(P(:,1)),'s','color','r');
						lines = houghlines(img, T, R, P,'FillGap',houghLinesFillGap,'MinLength',houghLinesMinLength);
					end
					set(parentFigure,'CurrentAxes',workingax);
					delete(findall(parentFigure,'tag','tmphough'));
					if isfield(lines,'point1') %Successfully captured at least one line
						hold on
						for k = 1:length(lines)
							xy = [lines(k).point1; lines(k).point2];
							plot(xy(:,1),xy(:,2),'LineWidth',2,'Color','green','tag','tmphough');
							% Plot beginnings and ends of lines
							plot(xy(1,1),xy(1,2),'x','LineWidth',2,'Color','yellow','tag','tmphough');
							plot(xy(2,1),xy(2,2),'x','LineWidth',2,'Color','red','tag','tmphough');
						end
					end
				end
				lastCommand = ...
					{sprintf('[H,T,R] = hough(img,''Theta'',%0.2f:%0.2f:%0.2f,''RhoResolution'',%0.2f);',minTheta,thetaResVal,maxTheta,rhoResVal);
					sprintf('P = houghpeaks(H,%d,''threshold'',%0.2f,''NHoodSize'',[%d %d]);',numPeaksVal,houghPeakThresh,houghNHoodSize1,houghNHoodSize2);
					sprintf('lines = houghlines(img,T,R,P,''FillGap'',%d,''MinLength'',%d);\n',houghLinesFillGap,houghLinesMinLength);
					sprintf('%%%%VISUALIZATION:\nfigure;\nimshow(img);\nhold on;');
					sprintf('for ii = 1:length(lines)');
					sprintf('\txy = [lines(ii).point1; lines(ii).point2];');
					sprintf('\tplot(xy(:,1),xy(:,2),''LineWidth'',2,''Color'',''green'');\nend')};
				lastCommand = char(lastCommand);
				uwi = 0;
			case 'Regional/Extended Min/Max'
				img = original.img;
				ind = find(cell2mat(get(extType,'value')));
				requestedType = get(extType(ind),'string');%#ok
				ind = find(cell2mat(get(extDir,'value')));
				requestedDir = get(extDir(ind),'string');%#ok
				nConn = nConnOpts{get(nConnValue,'value')};
				h = get(hSldr,'value');
				switch requestedType
					case 'Extended'
						if strcmp(requestedDir,'Minimum')
							img = imextendedmin(img,h,nConn);
							lastCommand = sprintf('img = imextendedmin(img,%0.2f,%i);\n',h,nConn);
						else
							img = imextendedmax(img,h,nConn);
							lastCommand = sprintf('img = imextendedmax(img,%0.2f,%i);\n',h,nConn);
						end
					case 'Regional'
						%h = nConnOpts{get(nConnValue,'value')};
						if strcmp(requestedDir,'Minimum')
							img = imregionalmin(img,nConn);
							lastCommand = sprintf('img = imregionalmin(img,%d);',nConn);
						else
							img = imregionalmax(img,nConn);
							lastCommand = sprintf('img = imregionalmax(img,%d);',nConn);
						end
				end
				throwComment([requestedType '/' requestedDir ' Segmentation'],0,1);
				if size(img,3) ~= 1
					img = im2double(img);
					throwComment('Visualizing multidimensional logical mask AS DOUBLE',0,1);
				end
			case 'Chroma'
				throwComment('CHROMA',0,1);
			case 'thresholdLocally'
				%localThreshold = varargin{1};
				localThreshold = localThresh;
				autoblocksize = get(localThreshold(9),'value');
				if autoblocksize
					[M,N] = bestblk([size(img,1),size(img,2)]);
				else
					M = str2double(get(localThreshold(1),'string'));
					N = str2double(get(localThreshold(2),'string'));
				end
				BS(1) = str2double(get(localThreshold(3),'string'));
				BS(2) = str2double(get(localThreshold(4),'string'));
				tmp = {'replicate','symmetric'};
				PM = tmp{get(localThreshold(6),'value')};
				FF = str2double(get(localThreshold(8),'string'));
				img = thresholdLocally(img,[M N],...
					'BorderSize',[BS(1),BS(2)],...
					'PadPartialBlocks',get(localThreshold(5),'value') == 1,...
					'PadMethod',PM,...
					'TrimBorder',get(localThreshold(7),'value') == 1,...
					'FudgeFactor',FF);
				lastCommand = sprintf('imgOut = thresholdLocally(imgIn,[%d, %d],...\n\t''BorderSize'',[%d,%d],...\n\t''PadPartialBlocks'',%d,...\n\t''PadMethod'',''%s'',...\n\t''TrimBorder'',%d,...\n\t''FudgeFactor'',%0.2f);\n\n%% (If you haven''t already done so, please download ''thresholdLocally'' from the File Exchange!)',M,N,BS(1),BS(2),get(localThreshold(5),'value') == 1,PM,get(localThreshold(7),'value') == 1,FF);
			case 'calcColorMasks'
				nColors = round(get(nColorsSldr,'value'));
				throwComment(sprintf('Calculating %0.0f masks.....',nColors),0,1);
				rgbIndices = rgb2ind(img,nColors);
				% (rgbIndices ranges from 0 to nColors-1)
				nRows = ceil(sqrt(nColors));
				nCols = ceil(nColors/nRows);
				[hobjpos,hobjdim] = distributeObjects(nRows,0.025,0.975,0.01);
				[vobjpos,vobjdim] = distributeObjects(nCols,0.9,0.025,0.1);
				colorMaskAxHandles = gobjects(nColors,1);
				imHandles = colorMaskAxHandles;
				titleHandles = colorMaskAxHandles;
				delete(findall(gcf,'tag','colorMaskAx'));
				ind = 1;
				for jjsub = 1:nCols
					for iisub = 1:nRows
						colorMaskAxHandles(ind) = axes('parent',colorMaskPanel,...
							'units','normalized',...
							'pos',[hobjpos(iisub) vobjpos(jjsub) hobjdim vobjdim]);
						ind = ind + 1;
						if ind > nColors
							break
						end
					end
				end
				for iisub = 0:nColors-1
					tmp = ismember(rgbIndices,iisub);
					[m,n,~] = size(tmp);
					while m*n > 5e5
						tmp = imresize(tmp,0.7);
						[m,n,~] = size(tmp);
					end
					imHandles(iisub+1) = imshow(tmp,'parent',colorMaskAxHandles(iisub+1));
					titleHandles(iisub+1) = title(sprintf('%02d',iisub),'parent',colorMaskAxHandles(iisub+1),'color','w','fontsize',14,...
						'fontweight','b','backgroundcolor','r','buttondownfcn',@imSelected,'userdata',iisub,...
						'interpreter','none');
				end
				set(titleHandles,'hittest','on');
				set(colorMaskAxHandles,'box','on','linewidth',1,...
					'xcolor','y','ycolor','y','visible','on',...
					'xtick',[],'ytick',[],'tag','colorMaskAx')
				expandAxes(colorMaskAxHandles)
		end
		if uwi %Update Working Imgage?
			updateWorkingImg(img);
		end
		if usingGray
			throwComment('Operating on GRAYSCALE version',0,1);
		end
		throwComment('Ready',0,1);
		togglePointer('arrow');
	end %segment

	function setupPanel(requestedPanel,tier,rank)
		parent = mainTabCardHandles{tier}(rank);
		bgc = get(parent,'backgroundcolor');
		tmp = rgb2gray(bgc);
		if tmp(1) > 0.4
			txtc = [0 0 0];
		else
			txtc = [1 1 1];
		end
		switch requestedPanel{1} %Alphabetical listing
			case 'Color-Based'
				uicontrol(parent,...
					'style','text',...
					'string','SELECT NUMBER OF COLORS TO BEGIN:',...
					'position',[0.025 0.835 0.25 0.125],...
					'foregroundcolor',[0.043 0.52 0.78]*0.5,...
					'backgroundcolor',bgc,...
					'horizontalalignment','left',...
					'fontweight','bold',...
					'fontsize',9);
				nColorsSldr = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Number of Colors',...
					'pos',[0.275 0.855 0.35 0.125],...
					'units','normalized'},...
					{'backgroundcolor',bgc,...
					'min',2,'max',36,'value',12,...
					'callback',@processRequest,...
					'sliderstep',[1/34 3/34],'tag','calcColorMasks',...
					'tooltipstring',sprintf('Slide to select number of colors in which to quantize image.\nDefault = 12.\n\nRight-Click bar to reset to default.')},...
					{'backgroundcolor',bgc,'fontsize',7},...
					{'backgroundcolor',bgc,'fontsize',7},...
					'%0.0f');
				uicontrol(parent,'style','text','units','normalized',...
					'position',[0.025 0.785 0.95 0.05],...
					'string','Click index numbers (title) to toggle inclusion (''green'') or omission (''red'') of color masks:',...
					'fontweight','bold',...
					'foregroundcolor',txtc,...%[0.043 0.52 0.78]*0.5,...;%,...
					'horizontalalignment','l',...
					'backgroundcolor',bgc,'fontsize',8);
				colorMaskPanel = uipanel('parent',parent,...
					'pos',[0.025,0.025,0.95,0.775],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'borderType','etchedin');%'none'
				[objpos, objdim] = distributeObjects(3,0.025,0.975,0.025,1);
				uicontrol(parent,'style','text',...
					'units','normalized',...
					'position',[0.65 0.915 0.325 0.075],...
					'string','NOTE: The ''Manual Selection'' tab has been deprecated. Use the colorThresholder app instead!',...
					'horizontalalignment','l',...
					'backgroundcolor',bgc,...
					'fontsize',6);
				uicontrol('parent',parent,...
					'string','Launch ColorThresholder app',...
					'position',[0.65 0.855 0.325 0.0625],...
					'foregroundcolor',[0.043 0.52 0.78]*0.5,...
					'fontsize',8,'fontweight','bold',...
					'tag','launchColorThresholder',...
					'callback',@processRequest);
			case 'Edge'
				%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				% Edge Detection Segmentation
				%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
				edgeButtons = uibuttongroup(parent,...
					'Position',[0.05 0.825 0.9 0.125],...
					'backgroundcolor',bgc,'title','Algorithm');
				% Create radio buttons in the button group.
				allEdgeTypes = {'Sobel','Prewitt','Roberts','LOG','ZeroCross','Canny'};
				tmp = {sprintf('The Sobel method finds edges using the Sobel approximation to the derivative.\nIt returns edges at those points where the gradient of I is maximum.');
					sprintf('The Prewitt method finds edges using the Prewitt approximation to the derivative.\nIt returns edges at those points where the gradient of I is maximum.');
					sprintf('The Roberts method finds edges using the Roberts approximation to the derivative. \nIt returns edges at those points where the gradient of I is maximum.');
					'The Laplacian of Gaussian method finds edges by looking for zero crossings after filtering I with a Laplacian of Gaussian filter.';
					'The zero-cross method finds edges by looking for zero crossings after filtering I with a filter you specify.';
					sprintf('The Canny method finds edges by looking for local maxima of the gradient of I.\nThe gradient is calculated using the derivative of a Gaussian filter.\nThe method uses two thresholds, to detect strong and weak edges, and includes the weak edges in the output only if they are connected to strong edges.\nThis method is therefore less likely than the others to be fooled by noise, and more likely to detect true weak edges.')};
				edgeType = zeros(numel(allEdgeTypes,1));
				for ii = 0:numel(allEdgeTypes)-1
					edgeType(ii+1) = uicontrol('parent',edgeButtons,'Style','Radio','String',allEdgeTypes{ii+1},...
						'pos',[objpos(rem(ii,3)+1) 0.15+(0.5*(ii<3)) objdim 0.3],'HandleVisibility','off',...
						'backgroundcolor',bgc,'fontsize',defaultFontsize,'value',ii==0,...
						'tooltipstring',tmp{ii+1});
				end
				string = ' All Algorithms ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.75 0.9 0.05],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				[sensSldr,~,sensEdt] = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Sensitivity Threshold',...
					'pos',[0.05 0.625 0.6 0.125],...
					'units','normalized'},...
					{'backgroundcolor',colors(5,:),...
					'min',0,'max',1,'value',0.5,...
					'callback',@processRequest,'sliderstep',[0.001 0.05],...
					'tag','SensSldr',...
					'tooltipstring',sprintf('Specifies the sensitivity threshold for the selected edge detection method.\nedge ignores all edges that are not stronger than thresh.\nIf you do not specify thresh, or if thresh is empty ([]), edge chooses the value automatically.\n\nRight-Click bar to reset to default.')},...
					{'backgroundcolor',colors(5,:),'fontsize',defaultFontsize},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize},...
					'%0.3f');
				autoSens = uicontrol('parent',parent,'style','checkbox',...
					'value',1,'pos',[0.675 0.625 0.3 0.1],...
					'backgroundcolor',bgc,'string','Auto-set','fontsize',defaultFontsize,...
					'tooltipstring','Use default value');
				%
				string = ' Sobel, Prewitt ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.55 0.9 0.05],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				edgeDirs = uibuttongroup(parent,...
					'Position',[0.05 0.475 0.9 0.08],...
					'backgroundcolor',bgc,'title','Direction');
				edgeDir(1) = uicontrol('parent',edgeDirs,'Style','Radio',...
					'String','Horizontal',...
					'pos',[objpos(1) 0.2 objdim 0.6],'HandleVisibility','off',...
					'backgroundcolor',bgc,'fontsize',defaultFontsize);
				edgeDir(2) = uicontrol('parent',edgeDirs,'Style','Radio',...
					'String','Vertical',...
					'pos',[objpos(2) 0.2 objdim 0.6],'HandleVisibility','off',...
					'backgroundcolor',bgc,'fontsize',defaultFontsize);
				edgeDir(3) = uicontrol('parent',edgeDirs,'Style','Radio',...
					'String','Both',...
					'pos',[objpos(3) 0.2 objdim 0.6],'HandleVisibility','off',...
					'backgroundcolor',bgc,'fontsize',defaultFontsize);
				set(edgeDirs,'selectedObject',edgeDir(3));
				%
				string = ' LOG, Canny ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.4 0.9 0.05],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				[sigmaSldr,~,sigmaEdt] = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Sigma',...
					'pos',[0.05 0.275 0.6 0.125],...
					'units','normalized'},...
					{'backgroundcolor',colors(5,:),'min',0,'max',7,'value',2,'callback',@processRequest,...
					'sliderstep',[0.01 0.1],'tag','SigmaSldr',...
					'tooltipstr',sprintf('Sigma specifies the standard deviation of the Gaussian filter.\nIt is relevant to Canny and LOG edge-detection.\nSee the documentation for EDGE for details.\n\nRight-Click bar to reset to default.')},...
					{'backgroundcolor',colors(5,:),'fontsize',defaultFontsize},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize},...
					'%0.2f');
				autoSigma = uicontrol('parent',parent,'style','checkbox',...
					'value',1,'pos',[0.675 0.275 0.3 0.1],...
					'backgroundcolor',bgc,'string','Auto-set','fontsize',defaultFontsize,...
					'tooltipstring','Use default value');
				%
			case 'Hough Line/Circle'
				[objpos,objdim] = distributeObjects(3,0.965,0.325,0.11);
				string = ' Hough Function ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.92 0.9 0.05],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c','fontname','arial');
				HoughFcnPanel = uipanel('parent',parent,...
					'pos',[0.05,0.6625,0.9,0.265],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,'bordertype','none');
				parent = HoughFcnPanel;
				[Lobjpos,Lobjdim] = distributeObjects(2,1,0,0.05);
				thetaRes = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Theta Resolution',...
					'pos',[0 Lobjpos(1) 0.475 Lobjdim],...
					'units','normalized'},...
					{'backgroundcolor',bgc/2,'min',0,'max',90,...
					'value',1,'callback',@processRequest,...
					'sliderstep',[1/90 5/90],'tag','ThetaResSldr',...
					'tooltipstring',sprintf('''Theta'' specifies a vector of Hough transform theta (angle) values, specified on the interval [-90, 90) degrees.\nCalculated here as [ThetaMin:ThetaRes:ThetaMax]\n\nRight-Click bar to reset to default.')},...
					{'fontsize',defaultFontsize+1},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize+1},...
					'%0.1f');
				[thetaMin,~,~] = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Theta Minimum',...
					'pos',[0 Lobjpos(2) 0.475 Lobjdim],...
					'units','normalized'},...
					{'backgroundcolor',bgc/2,'min',-90,'max',90,...
					'value',-90,'callback',@processRequest,...
					'sliderstep',[1/180 5/180],'tag','ThetaMinSldr',...
					'tooltipstring',sprintf('''Theta'' specifies a vector of Hough transform theta (angle) values, specified on the interval [-90, 90) degrees.\nCalculated here as [ThetaMin:ThetaRes:ThetaMax].\n\nRight-Click bar to reset to default.')},...
					{'fontsize',defaultFontsize+1},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize+1},...
					'%0.1f');
				[thetaMax,~,~] = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Theta Maximum',...
					'pos',[0.525 Lobjpos(2) 0.475 Lobjdim],...
					'units','normalized'},...
					{'backgroundcolor',bgc/2,'min',-90,'max',90,...
					'value',90,'callback',@processRequest,...
					'sliderstep',[1/180 5/180],'tag','ThetaMaxSldr',...
					'tooltipstring',sprintf('''Theta'' specifies a vector of Hough transform theta (angle) values, specified on the interval [-90, 90) degrees.\nCalculated here as [ThetaMin:ThetaRes:ThetaMax].\n\nRight-Click bar to reset to default.')},...
					{'fontsize',defaultFontsize+1},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize},...
					'%0.1f');
				rhoRes = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Rho Resolution',...
					'pos',[0.525 Lobjpos(1) 0.475 Lobjdim],...
					'units','normalized'},...
					{'backgroundcolor',bgc/2,'min',0.1,'max',200,...
					'value',1,'callback',@processRequest,...
					'sliderstep',[1/90 5/90],'tag','ThetaResSldr',...
					'tooltipstring',sprintf('Real scalar on the interval (0, norm(size(BW)) ), specifying the spacing of the Hough transform bins along the rho axis.\nDefault: 1.\n\nRight-Click bar to reset to default.')},...
					{'fontsize',defaultFontsize},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize},...
					'%0.1f');
				% Reset Parent
				parent = mainTabCardHandles{tier}(rank);
				string = ' HoughPeaks Function ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 objpos(2)+objdim-0.13 0.9 0.05],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				HoughPeaksPanel = uipanel('parent',parent,...
					'pos',[0.05,0.52-0.065,0.9,0.14],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,'bordertype','none');
				parent = HoughPeaksPanel;
				editShift = 0.05;
				numPeaks = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Number of Peaks',...
					'pos',[0 0 0.475 1],...
					'units','normalized'},...
					{'backgroundcolor',bgc/2,'min',1,'max',200,...
					'value',1,'callback',@processRequest,...
					'sliderstep',[1/199 5/199],'tag','NumPeaksSldr',...
					'tooltipstring',sprintf('Numpeaks specifies the maximum number of peaks to identify.\nDefault = 1.\n\nRight-Click bar to reset to default.')},...
					{'fontsize',defaultFontsize},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize},...
					'%0.0f');
				uicontrol('parent',parent,'style','text','string','Peak Threshold:',...
					'pos',[0.4875 0.5 0.31 0.3],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,'horizontalalignment','r',...
					'tooltipstring',sprintf('Nonnegative scalar.\nValues of H below ''Threshold'' will not be considered to be peaks.\nThreshold can vary from 0 to Inf.\nDefault: 0.5*max(H(:))'));
				houghPeakOpts(1) = uicontrol('parent',parent,'style','edit',...
					'string',sprintf('%0.3f',0.5*max(original.img(:))),...
					'pos',[0.9 0.475+editShift 0.1 0.3],'tag','HoughPeakThresh');
				uicontrol('parent',parent,'style','text','string','Neighborhood Size:',...
					'pos',[0.4875 0.15 0.31 0.3],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,'horizontalalignment','r',...
					'tooltipstring',sprintf('Two-element vector of positive odd integers: [M N], specifying the size of the suppression neighborhood.\nThis is the neighborhood around each peak that is set to zero after the peak is identified.\nDefault: smallest odd values >= size(H)/50'));
				nhood = size(original.img)/50;
				nhood = max(2*ceil(nhood/2) + 1, 1); % Make sure the nhood size is odd;
				houghPeakOpts(2) = uicontrol('parent',parent,'style','edit',...
					'string',sprintf('%0.0f',nhood(1)),...
					'pos',[0.81 0.15+editShift 0.075 0.3],'tag','HoughNHoodSize1');
				houghPeakOpts(3) = uicontrol('parent',parent,'style','edit','string',sprintf('%0.0f',nhood(2)),...
					'pos',[0.925 0.15+editShift 0.075 0.3],'tag','HoughNHoodSize2');
				% Reset Parent
				parent = mainTabCardHandles{tier}(rank);
				string = ' HoughLines Function ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 objpos(3)+objdim-0.085 0.9 0.05],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				HoughLinesPanel = uipanel('parent',parent,...
					'pos',[0.05,0.43-0.085,0.9,0.045],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,'bordertype','none');
				parent = HoughLinesPanel;
				editShift = 0.025;
				uicontrol('parent',parent,'style','text','string','Fill Gap:',...
					'pos',[0 0 0.2 1],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'horizontalalignment','l',...
					'tooltipstring',sprintf('When houghlines finds two line segments associated with the same Hough transform bin\nthat are separated by less than ''FillGap'' distance,\nhoughlines merges them into a single line segment.\nDefault: 20'));
				houghLinesOpts(1) = uicontrol('parent',parent,'style','edit',...
					'string',20,...
					'pos',[0.25 editShift 0.1 1],'tag','HoughLinesFillGap');
				uicontrol('parent',parent,'style','text','string','Minimum Length:',...
					'pos',[0.575 0 0.3 1],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,'horizontalalignment','l',...
					'tooltipstring',sprintf('Merged line segments shorter than ''MinLength'' are discarded.\nDefault: 40'));
				houghLinesOpts(2) = uicontrol('parent',parent,'style','edit','string',40,...
					'pos',[0.9 editShift 0.1 1],'tag','HoughLinesMinLength');
				% Reset Parent
				parent = mainTabCardHandles{tier}(rank);
				% Circular Hough
				string = ' Circular Hough ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.015 0.065 0.9 0.05],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				uicontrol(parent,'style','pushbutton',...
					'pos',[0.05 0.015 0.9 0.05],...
					'foregroundcolor',[0.043 0.52 0.78]*0.5,...
					'fontweight','bold',...
					'fontsize',defaultFontsize+1,...
					'string','Launch Circle Finder app','callback',@LaunchCircleFinder,...
					'tooltipstring',sprintf('Detect circles in image CURRENTLY DISPLAYED in main (working) axes.\n \n NOTE: Hough circle detection (IMFINDCIRCLES) was added to the Image Processing Toolbox in R2012a.\nThis button launches a standalone App for circle detection which must be downloaded and installed from MATLAB Central.\nIf you haven''t already, you should also upgrade to a post-R2011b version to use this functionality.'));
				houghAx = axes('parent',parent,'units','normalized','pos',[0.085 0.19 0.85 0.125],...
					'fontsize',defaultFontsize+1,'visible','off');
			case 'Regional/Extended Min/Max'
				[objpos,objdim] = distributeObjects(3,0.95,0.05,0.4);
				string = ' IMEXTENDEDMIN / IMEXTENDEDMAX ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.9 0.9 0.075],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				[hSldr,~,~] = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Height Threshold (Extended transforms)',...
					'pos',[0.05 0.755 0.6 0.15],...
					'units','normalized'},...
					{'backgroundcolor',colors(5,:),...
					'min',0,'max',1,'value',0.3,...
					'callback',@processRequest,...
					'sliderstep',[0.01 0.1],'tag','hSldr',...
					'tooltipstring',sprintf('See help for Hough.\nDefault = 0.3.\n\nRight-Click bar to reset to default.')},...
					{'backgroundcolor',colors(5,:),'fontsize',defaultFontsize},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize},...
					'%0.2f');
				string = ' EXTENDED and REGIONAL Min/Max Operations ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.645 0.9 0.075],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				minmaxButtons = uibuttongroup(parent,...
					'Position',[0.05 0.55 0.9 0.105],...
					'backgroundcolor',bgc,'title','Direction');
				extDir(1) = uicontrol('parent',minmaxButtons,'Style','Radio',...
					'String','Minimum',...
					'pos',[0.05 0.2 0.3 0.6],'HandleVisibility','off',...
					'backgroundcolor',bgc,'fontsize',defaultFontsize,'value',0);
				extDir(2) = uicontrol('parent',minmaxButtons,'Style','Radio',...
					'String','Maximum',...
					'pos',[0.5 0.2 0.3 0.6],'HandleVisibility','off',...
					'backgroundcolor',bgc,'fontsize',defaultFontsize,'value',0);
				regExtButtons = uibuttongroup(parent,...
					'Position',[0.05 0.425 0.9 0.105],...
					'backgroundcolor',bgc,'title','Type');
				extType(1) = uicontrol('parent',regExtButtons,'Style','Radio',...
					'String','Extended',...
					'pos',[0.05 0.2 0.3 0.6],'HandleVisibility','off',...
					'backgroundcolor',bgc,'fontsize',defaultFontsize,'value',0);
				extType(2) = uicontrol('parent',regExtButtons,'Style','Radio',...
					'String','Regional',...
					'pos',[0.5 0.2 0.2 0.6],'HandleVisibility','off',...
					'backgroundcolor',bgc,'fontsize',defaultFontsize,'value',0);
				string = ' IMREGIONALMIN / IMREGIONALMAX ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.33 0.9 0.075],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				nConnOpts = {4;8;6;18;26};
				nConnValue = uicontrol('parent',parent,'style','listbox',...
					'pos',[0.05 0.2 0.1 0.15],...
					'string',nConnOpts,...
					'backgroundcolor',bgc);
				if ~isrgb(original.img)
					set(nConnValue,'value',2);
				else
					set(nConnValue,'value',5);
				end
				uicontrol('parent',parent,'style','edit',...
					'pos',[0.2 0.2 0.75 0.15],'min',1,'max',3,'horizontalalignment','l',...
					'string',{'CONNECTIVITY:', 'IMREGIONALMIN and IMREGIONALMAX support any nonsparse, numeric class and any dimension.',...
					'By default, imregionalmin uses 8-connected neighborhoods for 2-D images and 26-connected neighborhoods for 3-D images. For higher dimensions, imregionalmin uses conndef(ndims(I),''maximal'')'});
			case 'Texture-Based'
				% Reset Parent
				%parent = mainTabCardHandles{tier}(rank);
				%bgc = colors(6,:);
				uicontrol(parent,'style','text','units','normalized',...
					'position',[0.025 0.79 0.95 0.05],...
					'string','Click on index number (title) to include (''green'') or omit (''red'') color masks.',...
					'fontweight','bold',...
					'foregroundcolor',txtc,...%[0.043 0.52 0.78]*0.5,...;%,...
					'horizontalalignment','l',...
					'backgroundcolor',bgc,'fontsize',9);
			case 'Thresholding'
				[objpos,objdim] = distributeObjects(3,0.05,0.95,0.01);
				string = ' Global Thresholding ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.965 0.9 0.025],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				refreshHistax(parent);
				string = ' Multi-thresh / Imquantize ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.615 0.9 0.025],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				uicontrol(parent,...
					'style','text',...
					'string',{'Activate using ''Number of Thresholds'' slider,',...
					'then TOGGLE to select (+) or de-select (X) color(s) to create mask',...
					'(visible on ''Overlay'' image below):'},...
					'position',[0.05 0.515 0.9 0.0375+0.05],...
					'foregroundcolor',[0.043 0.52 0.78]*0.5,...
					'backgroundcolor',bgc,...
					'fontweight','bold',...
					'fontsize',8.5);
				multithreshSlider = ...
					sliderPanel(parent,...
					{'backgroundcolor',bgc,...
					'title','Number of Thresholds',...
					'pos',[0.05 0.375 0.9 0.15],...
					'units','normalized'},...
					{'backgroundcolor',bgc/2,'min',1,'max',19,...
					'value',1,'callback',@processRequest,...
					'sliderstep',[1/18 2/18],...
					'tag','multithreshSldr',...
					'tooltipstring',sprintf('Implements N thresholds./See help for ''multithresh'',''imquantize''.')},...
					{'fontsize',defaultFontsize+1},...
					{'backgroundcolor',bgc,'fontsize',defaultFontsize+1},...
					'%0.0f');
				multithreshIndexButtons = gobjects(20,1);
				[objpos,objdim] = distributeObjects(10,0.05,0.95,0.01);
				for ii = 1:20
					multithreshIndexButtons(ii) = uicontrol(parent,...
						'position',[objpos(mod(ii-1,10)+1) 0.305-(double(ii>10)*0.05) objdim 0.04],...
						'visible','off',...
						'string','X',...
						'fontweight','normal',...
						'fontsize',12,...
						'userdata',ii,...
						'callback',@selectMultithreshInds);
				end
				string = ' Local (BLOCKPROC-BASED) Otsu Thresholding ';
				uicontrol('parent',parent,'style','text',...
					'pos',[0.05 0.205-0.025 0.9 0.05],...
					'backgroundcolor',bgc,...
					'string',padString(string,stringWidth),...
					'fontsize',defaultFontsize+1,'foregroundcolor',txtc,...
					'horizontalalignment','c');
				uicontrol('parent',parent,'style','text',...
					'string','BlockSize >>>',...
					'pos',[0.5 0.1 0.4 0.05],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'horizontalalignment','l',...
					'tooltipstring','Specifies size of block [M, N] with which to process the image.');
				localThresh(1) = uicontrol('parent',parent,'style','edit',...
					'pos',[0.73 0.125 0.075 0.025],...
					'string',32,'foregroundcolor',txtc);
				localThresh(2) = uicontrol('parent',parent,'style','edit',...
					'pos',[0.865 0.125 0.075 0.025],...
					'string',32,'foregroundcolor',txtc);
				uicontrol('parent',parent,'style','text',...
					'string','BorderSize >>>',...
					'pos',[0.5 0.065 0.4 0.05],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'horizontalalignment','l',...
					'tooltipstring',sprintf('A two-element vector, [V H], specifying the amount of border pixels to add to each block. \nThe function adds V rows above and below each block and H columns left and right of each block.\nThe size of each resulting block will be: [M + 2*V, N + 2*H].\nBy default, the function automatically removes the border from the result of fun.\nSee the ''TrimBorder'' parameter for more information.\nThe function pads blocks with borders extending beyond the image edges with zeros.\nDefault: [0 0] (no border)'));
				localThresh(3) = uicontrol('parent',parent,'style','edit',...
					'pos',[0.73 0.09 0.075 0.025],...
					'string',6,'foregroundcolor',txtc);
				localThresh(4) = uicontrol('parent',parent,'style','edit',...
					'pos',[0.865 0.09 0.075 0.025],...
					'string',6,'foregroundcolor',txtc);
				uicontrol('parent',parent,'style','text',...
					'string','Pad Partial Blocks:',...
					'pos',[0.05 0.12 0.4 0.05],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'horizontalalignment','l',...
					'tooltipstring',sprintf('A logical scalar. When set to true, blockproc pads partial blocks to make them full-sized (M-by-N) blocks.\nPartial blocks arise when the image size is not exactly divisible by the block size.\nIf they exist, partial blocks lie along the right and bottom edge of the image.\nThe default is false, meaning that the function does not pad the partial blocks, but processes them as-is.\nblockproc uses zeros to pad partial blocks when necessary.\nDefault: false.'));
				localThresh(5) = uicontrol('parent',parent,'style','popupmenu',...
					'pos',[0.275 0.145 0.165 0.035],...
					'string',{'true','false'},'value',1,'foregroundcolor',txtc);
				uicontrol('parent',parent,'style','text',...
					'string','Pad Method:',...
					'pos',[0.05 0.075 0.4 0.05],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'horizontalalignment','l',...
					'tooltipstring',sprintf('The ''PadMethod'' determines how blockproc will pad the image boundary. Options are:\nX: Pads the image with a scalar (X) pad value. (By default X == 0.)\n''replicate'': Repeats border elements of image A.\n''symmetric'': Pads image A with mirror reflections of itself.'));
				localThresh(6) = uicontrol('parent',parent,'style','popupmenu',...
					'pos',[0.275 0.1 0.165 0.035],...
					'string',{'replicate','symmetric'},'value',1,'foregroundcolor',txtc);
				uicontrol('parent',parent,'style','text',...
					'string','Trim Border:',...
					'pos',[0.05 0.03 0.4 0.05],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'horizontalalignment','l',...
					'tooltipstring',sprintf('A logical scalar. When set to true, the blockproc function trims off border pixels from the output of the user function, fun.\nThe function removes V rows from the top and bottom of the output of fun, and H columns from the left and right edges.\nThe ''BorderSize'' parameter defines V and H.\nThe default is true, meaning that the blockproc function automatically removes borders from the fun output.'));
				localThresh(7) = uicontrol('parent',parent,'style','popupmenu',...
					'pos',[0.275 0.055 0.165 0.035],...
					'string',{'true','false'},'value',1,'foregroundcolor',txtc);
				uicontrol('parent',parent,'style','text',...
					'string','Fudge Factor:',...
					'pos',[0.05 -0.015 0.4 0.05],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'horizontalalignment','l',...
					'tooltipstring','Multiplier for graythresh value');
				localThresh(8) = uicontrol('parent',parent,'style','edit',...
					'pos',[0.275 0.01 0.165 0.03],...
					'string',1,'foregroundcolor',txtc);%here
				localThresh(9) = uicontrol('parent',parent,'style','checkbox',...
					'string','Auto-select Blocksize',...
					'pos',[0.5 0.15 0.35 0.05],...
					'backgroundcolor',bgc,'foregroundcolor',txtc,...
					'value',1,'tag','autoSelectBlocksize','tooltipstring','Use default value');
				set([localThresh(1),localThresh(2)],'callback',@clearAutoBlocksize);
				uicontrol('parent',parent,'style','pushbutton',...
					'pos',[0.5 0.01 0.45 0.065],...
					'backgroundcolor',bgc,...
					'foregroundcolor',[0.043 0.52 0.78]*0.5,...
					'string','Threshold Locally',...'cdata',buttonIcon,...
					'tag','thresholdLocally',...
					'fontsize',defaultFontsize+2,...
					'fontweight','bold',...
					'horizontalalignment','c','callback',...
					{@processRequest,'thresholdLocally',localThresh},...
					'tooltipstring','Use BLOCKPROC to calculate automatically block-wise (i.e., "local") threshold values');
			case 'Watershed'
			otherwise
				error('Unrecognized panel requested.')
		end
	end %setupPanel

	function selectMultithreshInds(hObj,varargin)
		if strcmp(get(hObj,'string'),'X')
			set(hObj,'string','+')
		else
			set(hObj,'string','X');
		end
		useInds = find(strcmp(get(multithreshIndexButtons,'string'),'+'));
		img = ismember(quantIndex,useInds);
		updateWorkingImg(quantizedImg);
		updateOverlay(img);
		throwComment('Ready',0,1);
		lastCommand = {sprintf('thresholds = multithresh(img,%i);',nThresholds);
			'[~,quantIndex] = imquantize(img,thresholds);';
			sprintf('mask = ismember(quantIndex,[%s]);',num2str(useInds'))};
		if usingGray
			lastCommand = ['img = rgb2gray(img);';lastCommand];
		end
		togglePointer('arrow');
	end %selectMultithreshInds

	function throwComment(commentString,beepOn,append)
		soundsOff = get(findobj(segtool,'tag','TurnOffSounds'),'checked');
		if nargin < 2
			beepOn = 0;
		end
		if nargin < 3
			append = 1;
		end
		if append
			currString   = get(commentBox,'string');
			currString   = char(cellstr({currString;commentString}));
			if all(double(currString(1,:)== 32))
				currString = currString(2:end,:);
			end
			set(commentBox,'string',currString);
		else
			set(commentBox,'string',commentString);
		end
		tmp              = size(get(commentBox,'string'),1);
		set(commentBox,'listboxtop',tmp,'value',tmp);
		
		if beepOn  && ~strcmp(soundsOff,'on')
			play(notification) %This seems to be the workaround for the issues with SOUND
		end
		drawnow;
	end %throwComment

	function toggleMenuItem(varargin)
		item = varargin{1};
		checked = '';
		switch get(item,'type')
			case 'uimenu'
				checked = get(item,'checked');
				if strcmp(checked,'on')
					set(item,'checked','off');
				else
					set(item,'checked','on');
				end
		end
		if strcmp(get(item,'Tag'),'DisableTooltips')
			tmp = sort(findall(segtool));
			if strcmp(checked,'off') %Now turned on
				allTooltips = cell(numel(tmp),1);
				for tmpind = 1:numel(tmp)
					try %#ok
						allTooltips{tmpind} = get(tmp(tmpind),'tooltipstring');
						set(tmp(tmpind),'tooltipstring','');
					end
				end
			else
				for tmpind = 1:numel(tmp)
					try  %#ok
						set(tmp(tmpind),'tooltipstring',allTooltips{tmpind});
					end
				end
			end
		end
	end %toggleMenuItem

	function togglePointer(pType)
		if nargin == 0 || isempty(pType)
			if strcmp(get(gcf,'pointer'),'arrow')
				set(gcf,'pointer','watch');
			else
				set(gcf,'pointer','arrow');
			end
		else
			set(gcf,'pointer',pType);
		end
		drawnow;
	end %togglePointer

	function updateOverlay(varargin)
		% Updates OVERLAY display
		% Takes one input: binary mask to OVERLAY
		% If OVERLAY is empty, mask is cleared; otherwise, it is written
		overlay = varargin{1};
		if isempty(overlay)
			delete(findall(overlayax,'tag','opaqueOverlay'))
		else
			set(parentFigure,'CurrentAxes',overlayax);
			overlayColor = getappdata(overlayColorButton,'overlayColor');
			opacity = get(overlayOpacitySldr,'value');
			if isequal(size(overlay),size(original.grayversion))
				showMaskAsOverlay(opacity,overlay,overlayColor,overlayax);
			else
				updateOverlay([])
				throwComment('The mask size does not match the image size...I can''t overlay it!',1,1)
			end
			expandAxes(overlayax);
		end
	end %updateOverlay

	function updateWorkingImg(img,cmap,fname,updateOriginal)
		% UPDATES Main working axis, and image therein
		% INPUTS:
		%     IMG................Image DISPLAYED in working ax
		%     CMAP...............If nonempty, modifies display of IMG
		%     FNAME..............Modifies display of filename
		%     UPDATEORIGINAL.....Overwrites data stored in original.img
		
		% DEFAULTS
		if nargin <  3 || isempty(fname)
			fname = 'Original';
		end
		if nargin < 4 || isempty(updateOriginal)
			updateOriginal = 0;
		end
		if strcmp(fname,'FromMorphTool')
			img = imhandles(workingax);
			img = get(img,'cdata');
			updateOriginal = true;
		end
		if updateOriginal
			% Update data stored in ORIGINAL data structure
			img = im2double(img);
			original.img = img;
			if isrgb(img)
				original.grayversion = rgb2gray(img);
			else
				original.grayversion = img;
			end
			original.cmap = cmap;
			% Update DISPLAY of ORIGAX
			delete(origax);
			origax = axes('parent',segtool,'pos', [0.02 0.03 0.1968 0.2]);
			set(parentFigure,'CurrentAxes',origax);
			cla;
			tmp = imshow(img,[],'parent',origax);
			expandAxes(origax);
			[~,fn,ext] = fileparts(fname);
			title([fn ext],'fontweight','bold');
			% Update display of OVERLAYAX
			delete(overlayax);
			%overlayPanel position = [0.26 0.02 0.32 0.25]
			%origax position =       [0.02 0.03 0.1968 0.2]
			overlayax = axes('parent',overlayPanel,'pos',[0.02 0.05 0.1968/0.32 0.2/0.25]);
			set(parentFigure,'CurrentAxes',overlayax);
			cla;
			original.overlayImgHndl = imshow(img,[],'parent',overlayax);
			expandAxes(overlayax);
			title('Overlay','fontweight','bold');
			%Update IMHIST on threshold panel:
			if ishandle(histax)
				refreshHistax(get(histax,'parent'))
			end
		end
		% Update WORKINGAX
		delete(workingax);
		workingax = axes('parent',segtool,'pos', [0.02 0.285 0.56 0.625]);
		set(parentFigure,'CurrentAxes',workingax);
		cla;
		tmp = imshow(img,[],'parent',workingax);
		expandAxes(workingax);
	end %updateWorkingImg

	function useThisImage(varargin)
		close(findobj('tag','tmpfig'));
		switch varargin{3}
			case 1
				updateWorkingImg(rgb2gray(original.img));
			case 2
				updateWorkingImg(original.img(:,:,1));
			case 3
				updateWorkingImg(original.img(:,:,2));
			case 4
				updateWorkingImg(original.img(:,:,3));
		end
		throwComment('To continue working with this modified image, you may "Commit" it using FILE->COMMIT, if you so desire.',1,1);
	end %useThisImage

end %NESTED SUBFUNCTIONS

% SUBFUNCTIONS (NOT NESTED)

function draggableBrief(h,endfcn)
%Adapted from: Draggable, by:
% =========================================================================
% Copyright (C) 2003-2012
% Francois Bouffard
% fbouffard@gmail.com
% =========================================================================
% Initialization of some default arguments
constraint = 'none';
p = [];
user_endfcn = endfcn;
% Fetching informations about the parent axes
axh = get(h,'Parent');
if iscell(axh)
	axh = axh{1};
end
fgh = ancestor(axh,'figure');
ax_xlim = get(axh,'XLim');
ax_ylim = get(axh,'YLim');
constraint = 'n';
p = [ax_xlim ax_ylim];

% Saving object's and parent figure's initial state
setappdata(h,'initial_userdata',get(h,'UserData'));
setappdata(h,'initial_objbdfcn',get(h,'ButtonDownFcn'));
setappdata(h,'initial_wbdfcn',get(fgh,'WindowButtonDownFcn'));
setappdata(h,'initial_wbufcn',get(fgh,'WindowButtonUpFcn'));
setappdata(h,'initial_wbmfcn',get(fgh,'WindowButtonMotionFcn'));

% Saving parameters
setappdata(h,'constraint_type',constraint);
setappdata(h,'constraint_parameters',p);
setappdata(h,'user_endfcn',user_endfcn);

% Setting the object's ButtonDownFcn
set(h,'ButtonDownFcn',@click_object);
	function click_object(obj,eventdata)
		% obj here is the object to be dragged and gcf is the object's parent
		% figure since the user clicked on the object
		setappdata(obj,'initial_position',get_position(obj));
		setappdata(obj,'initial_extent',compute_extent(obj));
		setappdata(obj,'initial_point',get(gca,'CurrentPoint'));
		set(gcf,'WindowButtonDownFcn',{@activate_movefcn,obj});
		set(gcf,'WindowButtonUpFcn',{@deactivate_movefcn,obj});
		activate_movefcn(gcf,eventdata,obj);
	end
	function activate_movefcn(obj,~,h)
		set(obj,'WindowButtonMotionFcn',{@movefcn,h});
	end
	function deactivate_movefcn(obj,~,h)
		% obj here is the figure containing the object
		% Setting the original MotionFcn, DuttonDownFcn and ButtonUpFcn back
		set(obj,'WindowButtonMotionFcn',getappdata(h,'initial_wbmfcn'));
		set(obj,'WindowButtonDownFcn',getappdata(h,'initial_wbdfcn'));
		set(obj,'WindowButtonUpFcn',getappdata(h,'initial_wbufcn'));
		% Executing the user's drag end function
		user_endfcn = getappdata(h,'user_endfcn');
		if ~isempty(user_endfcn)
			feval(user_endfcn,h);           % added by SMB, modified by FB
		end
	end
	function movefcn(~,~,h)
		threshvalIndicator = findall(gcf,'tag','threshvalIndicator');
		% obj here is the *figure* containing the object
		% Retrieving data saved in the figure
		% Reminder: "position" refers to the object position in the axes
		%           "point" refers to the location of the mouse pointer
		initial_point = getappdata(h,'initial_point');
		constraint = getappdata(h,'constraint_type');
		p = getappdata(h,'constraint_parameters');
		% Getting current mouse position
		current_point = get(gca,'CurrentPoint');
		% Computing mouse movement (dpt is [dx dy])
		cpt = current_point(1,1:2);
		ipt = initial_point(1,1:2);
		dpt = cpt - ipt;
		% Computing movement range and imposing movement constraints
		range = p;
		idpt = dpt;
		% Computing object extent in the [x y w h] format before and after moving
		initial_extent = getappdata(h,'initial_extent');
		new_extent = initial_extent + [dpt 0 0];
		% Verifying if old and new objects breach the allowed range in any
		% direction (see the function is_inside_range below)
		initial_inrange = is_inside_range(initial_extent,range);
		new_inrange = is_inside_range(new_extent,range);
		% In-line correction functions to dpt due to range violations
		xminc = @(dpt) [range(1) - initial_extent(1) dpt(2)];
		xmaxc = @(dpt) [range(2) - (initial_extent(1) + initial_extent(3)) dpt(2)];
		yminc = @(dpt) [dpt(1) range(3) - initial_extent(2)];
		ymaxc = @(dpt) [dpt(1) range(4) - (initial_extent(2) + initial_extent(4))];
		% % We build a list of corrections to apply
		corrections = {};
		if initial_inrange(1) && ~new_inrange(1)
			% was within, now out of xmin range -- add xminc
			corrections = [corrections {xminc}];
		end
		if initial_inrange(2) && ~new_inrange(2)
			% was within, now out of xmax range -- add xmaxc
			corrections = [corrections {xmaxc}];
		end
		if initial_inrange(3) && ~new_inrange(3)
			% was within, now out of ymin range -- add yminc
			corrections = [corrections {yminc}];
		end
		if initial_inrange(4) && ~new_inrange(4)
			% was within, now out of ymax range -- add ymaxc
			corrections = [corrections {ymaxc}];
		end
		% Just applying all corrections
		for c = corrections
			dpt = c{1}(dpt);
		end
		% Re-computing new position with modified dpt
		newpos = update_position(getappdata(h,'initial_position'),dpt);
		set(threshvalIndicator,'string',num2str(newpos(1),2))
		% Setting the new position which actually moves the object
		set_position(h,newpos);
	end
	function pos = get_position(obj)
		props = get(obj);
		if isfield(props,'Position')
			pos = props.Position;
		elseif isfield(props,'XData')
			pos = [props.XData(:)'; props.YData(:)'];
		else
			error('Unable to find position');
		end
	end
	function newpos = update_position(pos,dpt)
		newpos = pos;
		if size(pos,1) == 1 % [x y [z / w h]]
			newpos(1:2) = newpos(1:2) + dpt;
		else                % [xdata; ydata]
			newpos(1,:) = newpos(1,:) + dpt(1);
			newpos(2,:) = newpos(2,:) + dpt(2);
		end
	end
	function set_position(obj,pos)
		if size(pos,1) == 1 % 'Position' property
			set(obj,'Position',pos);
		else                % 'XData/YData' properties
			set(obj,'XData',pos(1,:),'YData',pos(2,:));
		end
	end
	function extent = compute_extent(obj)
		props = get(obj);
		if isfield(props,'Extent')
			extent = props.Extent;
		elseif isfield(props,'Position')
			extent = props.Position;
		elseif isfield(props,'XData')
			minx = min(props.XData);
			miny = min(props.YData);
			w = max(props.XData) - minx;
			h = max(props.YData) - miny;
			extent = [minx miny w h];
		else
			error('Unable to compute extent');
		end
	end
	function inrange = is_inside_range(extent,range)
		% extent is in the [x y w h] format
		% range is in the [xmin xmax ymin ymax] format
		% inrange is a 4x1 vector of boolean values corresponding to range limits
		inrange = [extent(1) >= range(1) ...
			extent(1) + extent(3) <= range(2) ...
			extent(2) >= range(3) ...
			extent(2) + extent(4) <= range(4)];
	end
end

function k = isodd(x)
if nargin ~=1||~isa(x,'double')||floor(x)~=x
	error('Function isodd requires a double argument, with all matrix elements integers.');
end
%k = x/2~=floor(x/2);
k = rem(x,2) ~= 0;
end

function string = padString(string,varargin)
string = ['«««««    ' upper(string) '    »»»»»'];
end