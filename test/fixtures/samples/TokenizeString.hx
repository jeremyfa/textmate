// Ported from vscode-textmate 9.2.0: src/grammar/tokenizeString.ts
// Original code Copyright (C) Microsoft Corporation, licensed under MIT.
// Modified: translated to Haxe. See README.md.

package textmate.grammar;

import textmate.OnigLib;
import textmate.Rule;
import textmate.grammar.Grammar;

class TokenizeStringResult {
    public final stack:StateStackImpl;
    public final stoppedEarly:Bool;

    public inline function new(stack:StateStackImpl, stoppedEarly:Bool) {
        this.stack = stack;
        this.stoppedEarly = stoppedEarly;
    }
}

private class IWhileCheckResult {
    public final stack:StateStackImpl;
    public final linePos:Int;
    public final anchorPosition:Int;
    public final isFirstLine:Bool;

    public inline function new(stack:StateStackImpl, linePos:Int, anchorPosition:Int, isFirstLine:Bool) {
        this.stack = stack;
        this.linePos = linePos;
        this.anchorPosition = anchorPosition;
        this.isFirstLine = isFirstLine;
    }
}

private class IMatchResult {
    public final captureIndices:Array<IOnigCaptureIndex>;
    public final matchedRuleId:RuleId;
    /** Only set for injection results (`IMatchInjectionsResult`). */
    public final priorityMatch:Bool;

    public inline function new(captureIndices:Array<IOnigCaptureIndex>, matchedRuleId:RuleId, priorityMatch:Bool) {
        this.captureIndices = captureIndices;
        this.matchedRuleId = matchedRuleId;
        this.priorityMatch = priorityMatch;
    }
}

class LocalStackElement {
    public final scopes:AttributedScopeStack;
    public final endPos:Int;

    public inline function new(scopes:AttributedScopeStack, endPos:Int) {
        this.scopes = scopes;
        this.endPos = endPos;
    }
}

class TokenizeString {
    /**
     * vscode-textmate uses ONIG_OPTION_NOT_BEGIN_STRING / NOT_BEGIN_POSITION only when this is true.
     */
    static inline var UseOnigurumaFindOptions = false;

    /**
     * Tokenize a string
     * @param grammar
     * @param lineText
     * @param isFirstLine
     * @param linePos
     * @param stack
     * @param lineTokens
     * @param checkWhileConditions
     * @param timeLimit Use `0` to indicate no time limit
     * @returns the StackElement or StackElement.TIME_LIMIT_REACHED if the time limit has been reached
     */
    public static function _tokenizeString(grammar:Grammar, lineText:OnigString, isFirstLine:Bool, linePos:Int, stack:StateStackImpl, lineTokens:LineTokens,
            checkWhileConditions:Bool, timeLimit:Int):TokenizeStringResult {
        var lineLength = lineText.content.length;

        var STOP = false;
        var anchorPosition = -1;

        if (checkWhileConditions) {
            var whileCheckResult = _checkWhileConditions(grammar, lineText, isFirstLine, linePos, stack, lineTokens);
            stack = whileCheckResult.stack;
            linePos = whileCheckResult.linePos;
            isFirstLine = whileCheckResult.isFirstLine;
            anchorPosition = whileCheckResult.anchorPosition;
        }

        var startTime = timeLimit != 0 ? haxe.Timer.stamp() : 0.0;
        while (!STOP) {
            if (timeLimit != 0) {
                var elapsedTime = (haxe.Timer.stamp() - startTime) * 1000.0;
                if (elapsedTime > timeLimit) {
                    return new TokenizeStringResult(stack, true);
                }
            }

            // scanNext(): potentially modifies linePos && anchorPosition

            var r = matchRuleOrInjections(grammar, lineText, isFirstLine, linePos, stack, anchorPosition);

            if (r == null) {
                // No match
                lineTokens.produce(stack, lineLength);
                STOP = true;
                continue;
            }

            var captureIndices:Array<IOnigCaptureIndex> = r.captureIndices;
            var matchedRuleId = r.matchedRuleId;

            var hasAdvanced = (captureIndices != null && captureIndices.length > 0) ? captureIndices[0].end > linePos : false;

            if (matchedRuleId == Rules.endRuleId) {
                // We matched the `end` for this rule => pop it
                var poppedRule:BeginEndRule = cast stack.getRule(grammar);

                lineTokens.produce(stack, captureIndices[0].start);
                stack = stack.withContentNameScopesList(stack.nameScopesList);
                handleCaptures(grammar, lineText, isFirstLine, stack, lineTokens, poppedRule.endCaptures, captureIndices);
                lineTokens.produce(stack, captureIndices[0].end);

                // pop
                var popped = stack;
                stack = stack.parent;
                anchorPosition = popped.getAnchorPos();

                if (!hasAdvanced && popped.getEnterPos() == linePos) {
                    // Grammar pushed & popped a rule without advancing

                    // See https://github.com/Microsoft/vscode-textmate/issues/12
                    // Let's assume this was a mistake by the grammar author and the intent was to continue in this state
                    stack = popped;

                    lineTokens.produce(stack, lineLength);
                    STOP = true;
                    continue;
                }
            } else {
                // We matched a rule!
                var _rule = grammar.getRule(matchedRuleId);

                lineTokens.produce(stack, captureIndices[0].start);

                var beforePush = stack;
                // push it on the stack rule
                var scopeName = _rule.getName(lineText.content, captureIndices);
                var nameScopesList = stack.contentNameScopesList.pushAttributed(scopeName, grammar);
                stack = stack.push(matchedRuleId, linePos, anchorPosition, captureIndices[0].end == lineLength, null, nameScopesList, nameScopesList);

                if (Std.isOfType(_rule, BeginEndRule)) {
                    var pushedRule:BeginEndRule = cast _rule;

                    handleCaptures(grammar, lineText, isFirstLine, stack, lineTokens, pushedRule.beginCaptures, captureIndices);
                    lineTokens.produce(stack, captureIndices[0].end);
                    anchorPosition = captureIndices[0].end;

                    var contentName = pushedRule.getContentName(lineText.content, captureIndices);
                    var contentNameScopesList = nameScopesList.pushAttributed(contentName, grammar);
                    stack = stack.withContentNameScopesList(contentNameScopesList);

                    if (pushedRule.endHasBackReferences) {
                        stack = stack.withEndRule(pushedRule.getEndWithResolvedBackReferences(lineText.content, captureIndices));
                    }

                    if (!hasAdvanced && beforePush.hasSameRuleAs(stack)) {
                        // Grammar pushed the same rule without advancing
                        stack = stack.pop();
                        lineTokens.produce(stack, lineLength);
                        STOP = true;
                        continue;
                    }
                } else if (Std.isOfType(_rule, BeginWhileRule)) {
                    var pushedRule:BeginWhileRule = cast _rule;

                    handleCaptures(grammar, lineText, isFirstLine, stack, lineTokens, pushedRule.beginCaptures, captureIndices);
                    lineTokens.produce(stack, captureIndices[0].end);
                    anchorPosition = captureIndices[0].end;
                    var contentName = pushedRule.getContentName(lineText.content, captureIndices);
                    var contentNameScopesList = nameScopesList.pushAttributed(contentName, grammar);
                    stack = stack.withContentNameScopesList(contentNameScopesList);

                    if (pushedRule.whileHasBackReferences) {
                        stack = stack.withEndRule(pushedRule.getWhileWithResolvedBackReferences(lineText.content, captureIndices));
                    }

                    if (!hasAdvanced && beforePush.hasSameRuleAs(stack)) {
                        // Grammar pushed the same rule without advancing
                        stack = stack.pop();
                        lineTokens.produce(stack, lineLength);
                        STOP = true;
                        continue;
                    }
                } else {
                    var matchingRule:MatchRule = cast _rule;

                    handleCaptures(grammar, lineText, isFirstLine, stack, lineTokens, matchingRule.captures, captureIndices);
                    lineTokens.produce(stack, captureIndices[0].end);

                    // pop rule immediately since it is a MatchRule
                    stack = stack.pop();

                    if (!hasAdvanced) {
                        // Grammar is not advancing, nor is it pushing/popping
                        stack = stack.safePop();
                        lineTokens.produce(stack, lineLength);
                        STOP = true;
                        continue;
                    }
                }
            }

            if (captureIndices[0].end > linePos) {
                // Advance stream
                linePos = captureIndices[0].end;
                isFirstLine = false;
            }
        }

        return new TokenizeStringResult(stack, false);
    }

    /**
     * Walk the stack from bottom to top, and check each while condition in this order.
     * If any fails, cut off the entire stack above the failed while condition. While conditions
     * may also advance the linePosition.
     */
    static function _checkWhileConditions(grammar:Grammar, lineText:OnigString, isFirstLine:Bool, linePos:Int, stack:StateStackImpl,
            lineTokens:LineTokens):IWhileCheckResult {
        var anchorPosition = (stack.beginRuleCapturedEOL ? 0 : -1);

        var whileRules:Null<Array<StateStackImpl>> = null;
        var node:Null<StateStackImpl> = stack;
        while (node != null) {
            var nodeRule = node.getRule(grammar);
            if (Std.isOfType(nodeRule, BeginWhileRule)) {
                if (whileRules == null) {
                    whileRules = [];
                }
                whileRules.push(node);
            }
            node = node.pop();
        }

        if (whileRules != null) {
            var whileRuleStack = whileRules.pop();
            while (whileRuleStack != null) {
                var whileRule:BeginWhileRule = cast whileRuleStack.getRule(grammar);
                var ruleScanner = prepareRuleWhileSearch(whileRule, grammar, whileRuleStack.endRule, isFirstLine, linePos == anchorPosition);
                var r = ruleScanner.findNextMatchSync(lineText, linePos, FindOption.None);

                if (r != null) {
                    var matchedRuleId = r.ruleId;
                    if (matchedRuleId != Rules.whileRuleId) {
                        // we shouldn't end up here
                        stack = whileRuleStack.pop();
                        break;
                    }
                    if (r.captureIndices != null && r.captureIndices.length > 0) {
                        lineTokens.produce(whileRuleStack, r.captureIndices[0].start);
                        handleCaptures(grammar, lineText, isFirstLine, whileRuleStack, lineTokens, whileRule.whileCaptures, r.captureIndices);
                        lineTokens.produce(whileRuleStack, r.captureIndices[0].end);
                        anchorPosition = r.captureIndices[0].end;
                        if (r.captureIndices[0].end > linePos) {
                            linePos = r.captureIndices[0].end;
                            isFirstLine = false;
                        }
                    }
                } else {
                    stack = whileRuleStack.pop();
                    break;
                }
                whileRuleStack = whileRules.pop();
            }
        }

        return new IWhileCheckResult(stack, linePos, anchorPosition, isFirstLine);
    }

    static function matchRuleOrInjections(grammar:Grammar, lineText:OnigString, isFirstLine:Bool, linePos:Int, stack:StateStackImpl,
            anchorPosition:Int):Null<IMatchResult> {
        // Look for normal grammar rule
        var matchResult = matchRule(grammar, lineText, isFirstLine, linePos, stack, anchorPosition);

        // Look for injected rules
        var injections = grammar.getInjections();
        if (injections.length == 0) {
            // No injections whatsoever => early return
            return matchResult;
        }

        var injectionResult = matchInjections(injections, grammar, lineText, isFirstLine, linePos, stack, anchorPosition);
        if (injectionResult == null) {
            // No injections matched => early return
            return matchResult;
        }

        if (matchResult == null) {
            // Only injections matched => early return
            return injectionResult;
        }

        // Decide if `matchResult` or `injectionResult` should win
        var matchResultScore = matchResult.captureIndices[0].start;
        var injectionResultScore = injectionResult.captureIndices[0].start;

        if (injectionResultScore < matchResultScore || (injectionResult.priorityMatch && injectionResultScore == matchResultScore)) {
            // injection won!
            return injectionResult;
        }
        return matchResult;
    }

    static function matchRule(grammar:Grammar, lineText:OnigString, isFirstLine:Bool, linePos:Int, stack:StateStackImpl, anchorPosition:Int):Null<IMatchResult> {
        var rule = stack.getRule(grammar);
        var ruleScanner = prepareRuleSearch(rule, grammar, stack.endRule, isFirstLine, linePos == anchorPosition);

        var r = ruleScanner.findNextMatchSync(lineText, linePos, FindOption.None);

        if (r != null) {
            return new IMatchResult(r.captureIndices, r.ruleId, false);
        }
        return null;
    }

    static function matchInjections(injections:Array<Injection>, grammar:Grammar, lineText:OnigString, isFirstLine:Bool, linePos:Int, stack:StateStackImpl,
            anchorPosition:Int):Null<IMatchResult> {
        // The lower the better
        var bestMatchRating = 2147483647;
        var bestMatchCaptureIndices:Null<Array<IOnigCaptureIndex>> = null;
        var bestMatchRuleId:RuleId = 0;
        var bestMatchResultPriority = 0;

        var scopes = stack.contentNameScopesList.getScopeNames();

        for (i in 0...injections.length) {
            var injection = injections[i];
            if (!injection.matcher(scopes)) {
                // injection selector doesn't match stack
                continue;
            }
            var rule = grammar.getRule(injection.ruleId);
            var ruleScanner = prepareRuleSearch(rule, grammar, null, isFirstLine, linePos == anchorPosition);
            var matchResult = ruleScanner.findNextMatchSync(lineText, linePos, FindOption.None);
            if (matchResult == null) {
                continue;
            }

            var matchRating = matchResult.captureIndices[0].start;
            if (matchRating >= bestMatchRating) {
                // Injections are sorted by priority, so the previous injection had a better or equal priority
                continue;
            }

            bestMatchRating = matchRating;
            bestMatchCaptureIndices = matchResult.captureIndices;
            bestMatchRuleId = matchResult.ruleId;
            bestMatchResultPriority = injection.priority;

            if (bestMatchRating == linePos) {
                // No more need to look at the rest of the injections.
                break;
            }
        }

        if (bestMatchCaptureIndices != null) {
            return new IMatchResult(bestMatchCaptureIndices, bestMatchRuleId, bestMatchResultPriority == -1);
        }

        return null;
    }

    static inline function prepareRuleSearch(rule:Rule, grammar:Grammar, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule {
        return rule.compileAG(grammar, endRegexSource, allowA, allowG);
    }

    static inline function prepareRuleWhileSearch(rule:BeginWhileRule, grammar:Grammar, endRegexSource:Null<String>, allowA:Bool, allowG:Bool):CompiledRule {
        return rule.compileWhileAG(grammar, endRegexSource, allowA, allowG);
    }

    static function handleCaptures(grammar:Grammar, lineText:OnigString, isFirstLine:Bool, stack:StateStackImpl, lineTokens:LineTokens,
            captures:Array<Null<CaptureRule>>, captureIndices:Array<IOnigCaptureIndex>):Void {
        if (captures.length == 0) {
            return;
        }

        var lineTextContent = lineText.content;

        var len = captures.length < captureIndices.length ? captures.length : captureIndices.length;
        var localStack:Array<LocalStackElement> = [];
        var maxEnd = captureIndices[0].end;

        for (i in 0...len) {
            var captureRule = captures[i];
            if (captureRule == null) {
                // Not interested
                continue;
            }

            var captureIndex = captureIndices[i];

            if (captureIndex.length == 0) {
                // Nothing really captured
                continue;
            }

            if (captureIndex.start > maxEnd) {
                // Capture going beyond consumed string
                break;
            }

            // pop captures while needed
            while (localStack.length > 0 && localStack[localStack.length - 1].endPos <= captureIndex.start) {
                // pop!
                lineTokens.produceFromScopes(localStack[localStack.length - 1].scopes, localStack[localStack.length - 1].endPos);
                localStack.pop();
            }

            if (localStack.length > 0) {
                lineTokens.produceFromScopes(localStack[localStack.length - 1].scopes, captureIndex.start);
            } else {
                lineTokens.produce(stack, captureIndex.start);
            }

            if (captureRule.retokenizeCapturedWithRuleId != 0) {
                // the capture requires additional matching
                var scopeName = captureRule.getName(lineTextContent, captureIndices);
                var nameScopesList = stack.contentNameScopesList.pushAttributed(scopeName, grammar);
                var contentName = captureRule.getContentName(lineTextContent, captureIndices);
                var contentNameScopesList = nameScopesList.pushAttributed(contentName, grammar);

                var stackClone = stack.push(captureRule.retokenizeCapturedWithRuleId, captureIndex.start, -1, false, null, nameScopesList, contentNameScopesList);
                var onigSubStr = grammar.createOnigString(lineTextContent.substring(0, captureIndex.end));
                _tokenizeString(grammar, onigSubStr, (isFirstLine && captureIndex.start == 0), captureIndex.start, stackClone, lineTokens, false, /* no time limit */ 0);
                OnigLib.disposeOnigString(onigSubStr);
                continue;
            }

            var captureRuleScopeName = captureRule.getName(lineTextContent, captureIndices);
            if (captureRuleScopeName != null) {
                // push
                var base = localStack.length > 0 ? localStack[localStack.length - 1].scopes : stack.contentNameScopesList;
                var captureRuleScopesList = base.pushAttributed(captureRuleScopeName, grammar);
                localStack.push(new LocalStackElement(captureRuleScopesList, captureIndex.end));
            }
        }

        while (localStack.length > 0) {
            // pop!
            lineTokens.produceFromScopes(localStack[localStack.length - 1].scopes, localStack[localStack.length - 1].endPos);
            localStack.pop();
        }
    }
}
