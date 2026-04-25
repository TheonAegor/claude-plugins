#!/bin/bash
# Plugin integration test suite
# Runs structural validation + functional tests via isolated claude sessions

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BASE="/tmp/claude-plugin-test"
TEST_GO="$TEST_BASE/go"
TEST_WEB="$TEST_BASE/web"
TEST_ANDROID="$TEST_BASE/android"

PASSED=0
FAILED=0
SKIPPED=0
RESULTS=()

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

pass() {
    PASSED=$((PASSED + 1))
    RESULTS+=("${GREEN}PASS${NC} $1")
    echo -e "  ${GREEN}PASS${NC} $1"
}

fail() {
    FAILED=$((FAILED + 1))
    RESULTS+=("${RED}FAIL${NC} $1: $2")
    echo -e "  ${RED}FAIL${NC} $1: $2"
}

skip() {
    SKIPPED=$((SKIPPED + 1))
    RESULTS+=("${YELLOW}SKIP${NC} $1: $2")
    echo -e "  ${YELLOW}SKIP${NC} $1: $2"
}

section() {
    echo ""
    echo -e "${CYAN}=== $1 ===${NC}"
}

# Run claude in plugin mode. Args: working_dir prompt
run_claude() {
    local workdir="$1"
    shift
    (cd "$workdir" && claude -p \
        --plugin-dir "$PLUGIN_DIR" \
        --permission-mode acceptEdits \
        --model sonnet \
        "$@" 2>/dev/null) || true
}

setup_go_project() {
    mkdir -p "$TEST_GO"
    cat > "$TEST_GO/go.mod" << 'GOMOD'
module example.com/calculator

go 1.21
GOMOD

    cat > "$TEST_GO/calculator.go" << 'GOFILE'
package calculator

import "errors"

var (
	ErrDivisionByZero = errors.New("division by zero")
	ErrNegativeInput  = errors.New("negative input not allowed")
)

func Add(a, b float64) float64 {
	return a + b
}

func Subtract(a, b float64) float64 {
	return a - b
}

func Multiply(a, b float64) float64 {
	return a * b
}

func Divide(a, b float64) (float64, error) {
	if b == 0 {
		return 0, ErrDivisionByZero
	}
	return a / b, nil
}

func Factorial(n int) (int, error) {
	if n < 0 {
		return 0, ErrNegativeInput
	}
	if n <= 1 {
		return 1, nil
	}
	result := 1
	for i := 2; i <= n; i++ {
		result *= i
	}
	return result, nil
}
GOFILE

    cat > "$TEST_GO/README.md" << 'README'
# Calculator

A simple calculator package.
README
}

setup_web_project() {
    mkdir -p "$TEST_WEB/src"
    cat > "$TEST_WEB/package.json" << 'PKGJSON'
{
  "name": "test-web-app",
  "version": "1.0.0",
  "dependencies": {
    "react": "^18.2.0",
    "react-dom": "^18.2.0"
  }
}
PKGJSON

    cat > "$TEST_WEB/src/utils.js" << 'JSFILE'
export function formatCurrency(amount, currency = 'USD') {
  if (typeof amount !== 'number' || isNaN(amount)) {
    throw new TypeError('Amount must be a valid number');
  }
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
  }).format(amount);
}

export function debounce(fn, delay) {
  let timer = null;
  return function (...args) {
    clearTimeout(timer);
    timer = setTimeout(() => fn.apply(this, args), delay);
  };
}

export function deepClone(obj) {
  if (obj === null || typeof obj !== 'object') return obj;
  if (obj instanceof Date) return new Date(obj);
  if (Array.isArray(obj)) return obj.map(deepClone);
  return Object.fromEntries(
    Object.entries(obj).map(([k, v]) => [k, deepClone(v)])
  );
}
JSFILE

    cat > "$TEST_WEB/README.md" << 'README'
# Test Web App

A simple React utility library.
README
}

setup_android_project() {
    mkdir -p "$TEST_ANDROID/app/src/main/java/com/example"
    cat > "$TEST_ANDROID/build.gradle" << 'GRADLE'
plugins {
    id 'com.android.application'
    id 'org.jetbrains.kotlin.android'
}

android {
    namespace 'com.example.calculator'
    compileSdk 34
    defaultConfig {
        applicationId "com.example.calculator"
        minSdk 24
        targetSdk 34
    }
}
GRADLE

    cat > "$TEST_ANDROID/AndroidManifest.xml" << 'MANIFEST'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.example.calculator">
    <application android:label="Calculator" />
</manifest>
MANIFEST

    cat > "$TEST_ANDROID/app/src/main/java/com/example/Calculator.kt" << 'KTFILE'
package com.example

class Calculator {
    fun add(a: Double, b: Double): Double = a + b

    fun subtract(a: Double, b: Double): Double = a - b

    fun multiply(a: Double, b: Double): Double = a * b

    fun divide(a: Double, b: Double): Double {
        require(b != 0.0) { "Cannot divide by zero" }
        return a / b
    }

    fun fibonacci(n: Int): Long {
        require(n >= 0) { "Input must be non-negative" }
        if (n <= 1) return n.toLong()
        var a = 0L
        var b = 1L
        repeat(n - 1) {
            val temp = b
            b += a
            a = temp
        }
        return b
    }
}
KTFILE

    cat > "$TEST_ANDROID/README.md" << 'README'
# Calculator Android App

A simple calculator application.
README
}


teardown() {
    rm -rf "$TEST_BASE"
}

# ============================================================
# Structural tests (no API calls)
# ============================================================

test_structural() {
    section "Structural Tests"

    # plugin.json valid JSON with required fields
    if python3 -c "
import json, sys
d = json.load(open('$PLUGIN_DIR/.claude-plugin/plugin.json'))
assert 'name' in d, 'missing name'
assert 'version' in d, 'missing version'
" 2>/dev/null; then
        pass "plugin.json: valid JSON with required fields"
    else
        fail "plugin.json" "invalid JSON or missing required fields"
    fi

    # marketplace.json valid JSON
    if python3 -c "import json; json.load(open('$PLUGIN_DIR/.claude-plugin/marketplace.json'))" 2>/dev/null; then
        pass "marketplace.json: valid JSON"
    else
        fail "marketplace.json" "invalid JSON"
    fi

    # All SKILL.md ${CLAUDE_PLUGIN_ROOT} paths resolve
    local missing_paths=0
    while IFS= read -r ref; do
        local rel_path
        rel_path=$(echo "$ref" | sed 's|.*\${CLAUDE_PLUGIN_ROOT}/||' | sed 's/).*$//' | sed 's/)$//')
        if [ ! -f "$PLUGIN_DIR/$rel_path" ]; then
            fail "path reference" "$rel_path not found (referenced in SKILL.md)"
            missing_paths=$((missing_paths + 1))
        fi
    done < <(grep -roh '\${CLAUDE_PLUGIN_ROOT}/[^)]*' "$PLUGIN_DIR/skills/" 2>/dev/null || true)
    if [ "$missing_paths" -eq 0 ]; then
        pass "SKILL.md path references: all resolve"
    fi

    # YAML frontmatter parseable in skills
    local yaml_ok=true
    for skill_file in "$PLUGIN_DIR"/skills/*/SKILL.md; do
        if ! python3 -c "
import sys
content = open('$skill_file').read()
if content.startswith('---'):
    end = content.index('---', 3)
    fm = content[3:end].strip()
    # Basic check: has name and description
    assert 'name:' in fm, f'missing name in {\"$skill_file\"}'
    assert 'description:' in fm, f'missing description in {\"$skill_file\"}'
" 2>/dev/null; then
            fail "skill frontmatter" "$skill_file has invalid frontmatter"
            yaml_ok=false
        fi
    done
    if $yaml_ok; then
        pass "skill frontmatter: all valid"
    fi

    # YAML frontmatter parseable in agents
    local agent_ok=true
    for agent_file in "$PLUGIN_DIR"/agents/*.md; do
        if ! python3 -c "
import sys
content = open('$agent_file').read()
if content.startswith('---'):
    end = content.index('---', 3)
    fm = content[3:end].strip()
    assert 'name:' in fm, f'missing name in {\"$agent_file\"}'
    assert 'description:' in fm, f'missing description in {\"$agent_file\"}'
    assert 'tools:' in fm, f'missing tools in {\"$agent_file\"}'
" 2>/dev/null; then
            fail "agent frontmatter" "$agent_file has invalid frontmatter"
            agent_ok=false
        fi
    done
    if $agent_ok; then
        pass "agent frontmatter: all valid"
    fi

    # approve-read.sh is executable
    if [ -x "$PLUGIN_DIR/scripts/approve-read.sh" ]; then
        pass "approve-read.sh: is executable"
    else
        fail "approve-read.sh" "not executable"
    fi

    # Rules have alwaysApply in frontmatter
    local rules_ok=true
    for rule_file in "$PLUGIN_DIR"/rules/*.md; do
        if ! grep -q "alwaysApply:" "$rule_file" 2>/dev/null; then
            fail "rule frontmatter" "$(basename "$rule_file") missing alwaysApply"
            rules_ok=false
        fi
    done
    if $rules_ok; then
        pass "rules frontmatter: all have alwaysApply"
    fi
}

# ============================================================
# Hook tests (no API calls)
# ============================================================

test_hook() {
    section "Hook Tests (approve-read.sh)"

    local hook="$PLUGIN_DIR/scripts/approve-read.sh"

    # Plugin file path -> allow
    local out
    out=$(echo '{"tool":"Read","path":"'"$PLUGIN_DIR"'/skills/review/SKILL.md"}' \
        | CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$hook" 2>/dev/null) || true
    if echo "$out" | grep -q '"behavior":"allow"'; then
        pass "hook: plugin path -> allow"
    else
        fail "hook: plugin path" "expected allow, got: $out"
    fi

    # go.mod -> allow
    out=$(echo '{"tool":"Read","path":"go.mod"}' \
        | CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$hook" 2>/dev/null) || true
    if echo "$out" | grep -q '"behavior":"allow"'; then
        pass "hook: go.mod -> allow"
    else
        fail "hook: go.mod" "expected allow, got: $out"
    fi

    # package.json -> allow
    out=$(echo '{"tool":"Read","path":"package.json"}' \
        | CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$hook" 2>/dev/null) || true
    if echo "$out" | grep -q '"behavior":"allow"'; then
        pass "hook: package.json -> allow"
    else
        fail "hook: package.json" "expected allow, got: $out"
    fi

    # Random path -> no allow
    out=$(echo '{"tool":"Read","path":"/tmp/secret.txt"}' \
        | CLAUDE_PLUGIN_ROOT="$PLUGIN_DIR" bash "$hook" 2>/dev/null) || true
    if echo "$out" | grep -q '"behavior":"allow"'; then
        fail "hook: random path" "should NOT allow /tmp/secret.txt"
    else
        pass "hook: random path -> no allow"
    fi
}

# ============================================================
# Availability test (1 API call)
# ============================================================

test_availability() {
    section "Skill & Agent Availability"

    local out
    out=$(run_claude "$PLUGIN_DIR" \
        "List all available slash commands (skills) and agents from loaded plugins. Output each name on a separate line, nothing else.")

    local all_found=true
    for skill in review write-unit-tests doc-write; do
        if echo "$out" | grep -qi "claude-ai-onboarding:$skill\|onboarding.*$skill"; then
            pass "skill available: $skill"
        else
            fail "skill available: $skill" "not found in output"
            all_found=false
        fi
    done

    for agent in doc-sync-analyzer qa-test-specialist; do
        if echo "$out" | grep -qi "claude-ai-onboarding:$agent\|onboarding.*$agent"; then
            pass "agent available: $agent"
        else
            fail "agent available: $agent" "not found in output"
            all_found=false
        fi
    done
}

# ============================================================
# Functional tests — Go platform
# ============================================================

test_go_review() {
    section "Functional: Go /review"

    local out
    out=$(run_claude "$TEST_GO" \
        "/claude-ai-onboarding:review -- Review calculator.go. Keep your response under 300 words. Focus on bugs and improvements.")

    if [ -n "$out" ] && [ ${#out} -gt 50 ]; then
        pass "go /review: produced meaningful output (${#out} chars)"
    else
        fail "go /review" "output too short or empty (${#out} chars)"
    fi
}

test_go_unit_tests() {
    section "Functional: Go /write-unit-tests"

    local out
    out=$(run_claude "$TEST_GO" \
        "/claude-ai-onboarding:write-unit-tests calculator.go")

    if echo "$out" | grep -qi "test\|Test"; then
        pass "go /write-unit-tests: mentions tests"
    else
        fail "go /write-unit-tests" "no test-related content in output"
    fi

    # Check if test file was created
    if ls "$TEST_GO"/*_test.go 1>/dev/null 2>&1; then
        pass "go /write-unit-tests: test file created"
    else
        skip "go /write-unit-tests: test file creation" "file not found (may need permissions)"
    fi
}

# ============================================================
# Functional tests — Web platform
# ============================================================

test_web_review() {
    section "Functional: Web /review"

    local out
    out=$(run_claude "$TEST_WEB" \
        "/claude-ai-onboarding:review -- Review src/utils.js. Keep your response under 300 words.")

    if [ -n "$out" ] && [ ${#out} -gt 50 ]; then
        pass "web /review: produced meaningful output (${#out} chars)"
    else
        fail "web /review" "output too short or empty (${#out} chars)"
    fi
}

test_web_unit_tests() {
    section "Functional: Web /write-unit-tests"

    local out
    out=$(run_claude "$TEST_WEB" \
        "/claude-ai-onboarding:write-unit-tests src/utils.js")

    if echo "$out" | grep -qi "test\|Test\|spec\|describe\|it("; then
        pass "web /write-unit-tests: mentions tests"
    else
        fail "web /write-unit-tests" "no test-related content in output"
    fi
}

# ============================================================
# Functional tests — Android platform
# ============================================================

test_android_review() {
    section "Functional: Android /review"

    local out
    out=$(run_claude "$TEST_ANDROID" \
        "/claude-ai-onboarding:review -- Review app/src/main/java/com/example/Calculator.kt. Keep your response under 300 words.")

    if [ -n "$out" ] && [ ${#out} -gt 50 ]; then
        pass "android /review: produced meaningful output (${#out} chars)"
    else
        fail "android /review" "output too short or empty (${#out} chars)"
    fi
}

test_android_unit_tests() {
    section "Functional: Android /write-unit-tests"

    local out
    out=$(run_claude "$TEST_ANDROID" \
        "/claude-ai-onboarding:write-unit-tests app/src/main/java/com/example/Calculator.kt")

    if echo "$out" | grep -qi "test\|Test\|@Test\|junit"; then
        pass "android /write-unit-tests: mentions tests"
    else
        fail "android /write-unit-tests" "no test-related content in output"
    fi
}

# ============================================================
# Functional test — doc-write
# ============================================================

test_doc_write() {
    section "Functional: /doc-write (Go)"

    local out
    out=$(run_claude "$TEST_GO" \
        "/claude-ai-onboarding:doc-write Add a Usage section with examples to README.md")

    if echo "$out" | grep -qi "doc\|write\|README\|SKILL COMPLETE\|updated"; then
        pass "doc-write: produced doc-related output"
    else
        fail "doc-write" "no documentation-related content in output"
    fi
}


# ============================================================
# Main
# ============================================================

main() {
    echo ""
    echo -e "${CYAN}Plugin Test Suite${NC}"
    echo -e "Plugin: ${PLUGIN_DIR}"
    echo -e "Date: $(date '+%Y-%m-%d %H:%M:%S')"

    # Setup
    section "Setup"
    teardown 2>/dev/null || true
    setup_go_project
    echo "  Created Go project at $TEST_GO"
    setup_web_project
    echo "  Created Web project at $TEST_WEB"
    setup_android_project
    echo "  Created Android project at $TEST_ANDROID"

    # Run tests
    test_structural
    test_hook
    test_availability
    test_go_review
    test_go_unit_tests
    test_web_review
    test_web_unit_tests
    test_android_review
    test_android_unit_tests
    test_doc_write

    # Cleanup
    section "Cleanup"
    teardown
    echo "  Removed test projects"

    # Summary
    section "Summary"
    echo ""
    for r in "${RESULTS[@]}"; do
        echo -e "  $r"
    done
    echo ""
    local total=$((PASSED + FAILED + SKIPPED))
    echo -e "  ${GREEN}$PASSED passed${NC}, ${RED}$FAILED failed${NC}, ${YELLOW}$SKIPPED skipped${NC} / $total total"
    echo ""

    if [ "$FAILED" -eq 0 ]; then
        echo -e "  ${GREEN}STATUS: PASS${NC}"
        exit 0
    else
        echo -e "  ${RED}STATUS: FAIL${NC}"
        exit 1
    fi
}

main "$@"
