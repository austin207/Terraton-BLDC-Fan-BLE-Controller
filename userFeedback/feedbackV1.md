# Terraton Smart BLDC Fan App – Consolidated UI/UX Feedback Report

## Overview

This document consolidates UI/UX feedback collected for the Terraton Smart BLDC Fan application. The feedback focuses on improving:

* Visual polish  
* Interaction clarity  
* User feedback responsiveness  
* Control intuitiveness  
* RPM/speed meter aesthetics  
* Boost mode visibility

---

# 1\. Splash Screen Improvements

## 1.1 Loading Indicator Animation

### Current Issue

The loading indicator at the bottom of the splash screen is currently static, making the launch experience feel less interactive.

### Suggested Improvements

Add subtle animation effects to improve perceived responsiveness and polish.

### Recommended Options

* Animated dots  
* Pulsing indicator  
* Soft fade-in/fade-out animation  
* Smooth looping motion

### Expected UX Benefit

* Makes the app feel more modern  
* Improves perceived loading responsiveness  
* Enhances first-launch experience

---

## 1.2 App Logo Edge Cleanup

### Current Issue

The app logo appears to contain visible white edges/background remnants.

### Areas Affected

* Splash Screen  
* My Fans Screen  
* Control Screen

### Suggested Improvements

* Remove white edge artifacts  
* Clean transparent edges  
* Improve logo rendering quality

### Expected UX Benefit

* More professional appearance  
* Cleaner branding presentation  
* Better visual consistency across screens

---

# 2\. Control Screen – Speed Button Improvements

## 2.1 Speed Button Width Consistency

### Current Issue

The speed selection buttons (1–6) in the new control screen feel less visually balanced compared to the old version.

### Old Version Strengths

* Better spacing  
* More consistent proportions  
* Cleaner alignment  
* Better visual harmony

### Suggested Improvements

* Match button proportions closer to the old design  
* Ensure consistent width and spacing  
* Improve overall layout symmetry

### Expected UX Benefit

* Cleaner control layout  
* Improved readability  
* More polished visual hierarchy

---

## 2.2 Speed Button Selection Logic

### Current Issue

Currently:

* Selecting Speed 2 highlights both Speed 1 and Speed 2  
* Multiple buttons appear active simultaneously

This creates confusion regarding the currently selected speed.

### Required Behavior

Only the currently selected speed button should appear active.

### Correct Examples

* Selecting Speed 2 → only “2” is highlighted  
* Selecting Speed 5 → only “5” is highlighted

All other buttons should remain inactive.

### Expected UX Benefit

* Clearer state indication  
* Reduced ambiguity  
* More intuitive interaction model

---

# 3\. Dial / RPM Meter Behavior

## 3.1 Progressive Dial Illumination

### Current Concept

The existing dial concept is visually effective.

### Preferred Behavior

When a speed level is selected, all dial segments up to that level should illuminate progressively.

### Example

* Speed 1 → first segment lights up  
* Speed 3 → first three segments light up  
* Speed 6 → all segments light up

### Expected UX Benefit

* Better visualization of speed progression  
* More dynamic interaction feedback  
* Improved readability of current speed state

---

# 4\. Operating Modes – Toggle Behavior

## Current Issue

Once an operating mode is selected, it cannot be deselected unless another mode is chosen.

### Current Limitation

Modes behave like mandatory single-selection options.

---

## Required Behavior

Operating modes should behave as independent toggle buttons.

### Desired Interaction

* Tap mode → activates mode  
* Tap same mode again → deactivates mode

### Example

* Tap “Nature” → Nature ON  
* Tap “Nature” again → Nature OFF

### Expected UX Benefit

* More flexible controls  
* More intuitive user interaction  
* Better usability consistency

---

# 5\. Boost Mode – Visibility & Active State Feedback

## 5.1 Current Implementation

### Existing Design

* Normal speed buttons:  
    
  * White by default  
  * Blue when selected


* Boost mode:  
    
  * Already blue by default

---

## Issue Identified

Since boost mode already uses a blue background in its default state, users may struggle to determine:

* whether boost mode is active, or  
* whether the button is simply showing its default appearance.

This weakens visual confirmation during operation.

---

## Suggested Improvements

Boost mode should have a significantly stronger and more distinguishable active-state appearance.

### Recommended Enhancements

When boost mode is enabled:

#### RPM Meter Enhancements

* Apply stronger visual feedback across the RPM/speed meter  
    
* Use energetic visual themes such as:  
    
  * Red  
  * Orange  
  * Warm gradients  
  * Dynamic lighting effects

#### Additional Visual Effects

* Glow effects  
* Pulse animations  
* Animated highlights  
* Meter-wide background transformation

#### UI Styling Suggestions

* Change entire RPM meter background during boost activation  
* Use aggressive energetic color accents  
* Make boost mode visually distinct from regular speed states

### Expected UX Benefit

* Clear boost activation visibility  
* Stronger emotional feedback  
* Better sense of high-performance mode activation

---

# 6\. RPM Meter – Color Transition & Visual Refinement

## Current Implementation

Current speed colors:

1. Green  
2. Blue  
3. Violet  
4. Yellow  
5. Orange  
6. Red

---

## Issue Identified

The current transitions feel:

* segmented  
* abrupt  
* visually disconnected

The RPM meter could feel more premium with smoother transitions and blended gradients.

---

## Suggested Improvements

### Improve Color Progression

Replace isolated solid colors with smoother gradient-based transitions.

### Suggested Gradient Flow

* Green → Cyan → Blue → Violet → Orange → Red

### Visual Enhancement Recommendations

* Smooth gradient blending  
* Glow effects  
* Animated transitions during speed changes  
* Enhanced RPM styling  
* More polished meter rendering  
* Better visual continuity between levels

### Expected UX Benefit

* More premium visual appearance  
* Better motion continuity  
* Smoother speed progression feedback  
* Enhanced modern UI feel

---

# 7\. Overall UX Direction

## Recommended Design Direction

The UI should aim for:

* Cleaner visual hierarchy  
* Stronger active-state feedback  
* More premium animations  
* Better motion design  
* Improved visual consistency  
* Clearer interaction states

---

# 8\. High-Priority Functional Fixes

## Must-Fix Interaction Issues

### Speed Button Logic

* Only one speed button active at a time

### Operating Mode Logic

* Allow toggling modes ON/OFF independently

### Boost Mode Visibility

* Stronger active-state differentiation

---

# 9\. Recommended Visual Enhancements Summary

## Animations

* Splash loading animation  
* RPM transition animation  
* Glow effects  
* Pulse effects  
* Smooth meter transitions

## Visual Polish

* Clean logo edges  
* Better gradients  
* Improved button spacing  
* Refined meter styling

## UX Clarity

* Clear active states  
* Progressive dial lighting  
* Better boost mode feedback  
* Intuitive toggle interactions
