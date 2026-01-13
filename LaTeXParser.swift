import Foundation

/// 改进后的 LaTeX 解析器 - 正确处理嵌套括号和命令
struct LaTeXParser {
    
    static func parse(_ text: String) -> String {
        // 1. 预处理：希腊字母和特殊符号 (无参数命令)
        let processed = replaceSymbols(text)
        
        // 2. 解析结构 (frac, sqrt, etc)
        // 将字符串转换为字符数组以便扫描
        let chars = Array(processed)
        var result = ""
        var i = 0
        
        while i < chars.count {
            let c = chars[i]
            
            if c == "\\" {
                // 读取命令
                let cmdStart = i
                i += 1
                var cmdName = ""
                while i < chars.count && (chars[i].isLetter) {
                    cmdName.append(chars[i])
                    i += 1
                }
                // 处理特殊命令字符 (如 \, \%, \$)
                if cmdName.isEmpty && i < chars.count {
                    cmdName.append(chars[i])
                    i += 1
                }
                
                // 处理命令
                if cmdName == "frac" {
                    // 解析两个参数 {num}{den}
                    let num = parseGroup(chars: chars, index: &i)
                    let den = parseGroup(chars: chars, index: &i)
                    result += "(\(num)/\(den))"
                } else if cmdName == "sqrt" {
                    // 解析可选参数 [n]
                    if i < chars.count && chars[i] == "[" {
                        // 跳过 [] 内容，暂时忽略次数
                        while i < chars.count && chars[i] != "]" { i += 1 }
                        if i < chars.count { i += 1 } // skip ]
                    }
                    let content = parseGroup(chars: chars, index: &i)
                    result += "√(\(content))"
                } else if cmdName == "text" || cmdName == "mathrm" || cmdName == "mathbf" {
                    // 仅保留内容
                    let content = parseGroup(chars: chars, index: &i)
                    result += content
                } else if cmdName == "left" || cmdName == "right" {
                    // 忽略 left/right, 继续解析下一个字符
                    // 通常后面跟着定界符，如 \left(
                    if i < chars.count {
                        let delimiter = chars[i]
                        // 保留括号，移除 .
                        if delimiter != "." {
                            result.append(delimiter)
                        }
                        i += 1
                    }
                } else if cmdName == "vec" {
                    // 向量：\vec{a} -> a⃗
                    let content = parseGroup(chars: chars, index: &i)
                    result += content + "⃗"
                } else if cmdName == "bar" || cmdName == "overline" {
                    let content = parseGroup(chars: chars, index: &i)
                    result += content + "̅" // combining overline
                } else if cmdName == "hat" {
                    let content = parseGroup(chars: chars, index: &i)
                    result += content + "̂" // combining hat
                } else if cmdName == "begin" {
                    // 解析环境
                    let envName = parseGroup(chars: chars, index: &i)
                    if envName.contains("matrix") || envName == "cases" {
                        // 矩阵处理逻辑
                        // 1. 提取环境内容直至 \end{envName}
                        var envContent = ""
                        let endTag = "\\end{\(envName)}"
                        // 简单向后查找
                        let remainder = String(chars[i...])
                        if let range = remainder.range(of: endTag) {
                            envContent = String(remainder[..<range.lowerBound])
                            i += remainder.distance(from: remainder.startIndex, to: range.upperBound)
                        } else {
                            // 未找到结尾，不做特殊处理
                            i += 1 
                        }
                        
                        // 2. 格式化矩阵：& -> "  ", \\ -> "\n"
                        // 简单 ASCII 风格
                        var formatted = " " + parse(envContent) + " " // 递归解析内容
                        formatted = formatted.replacingOccurrences(of: "&", with: "  ")
                        formatted = formatted.replacingOccurrences(of: "\\\\", with: "\n")
                        
                        result += "\n" + formatted + "\n"
                    }
                } else if cmdName == "end" {
                    // end在begin中被处理了，如果这里出现说明是 unmatched，忽略
                    _ = parseGroup(chars: chars, index: &i)
                } else if cmdName == "quad" || cmdName == "qquad" || cmdName == "," || cmdName == ";" {
                    result += " "
                } else if cmdName == "$" || cmdName == "#" || cmdName == "%" || cmdName == "&" {
                    result += cmdName // 恢复转义字符
                } else {
                    // 未知命令，恢复原文：保留反斜杠+命令名
                    result += "\\" + cmdName
                }
                // 忽略顶层的结构大括号
                i += 1
            } else if c == "^" {
                // 上标
                i += 1
                let sup = parseArg(chars: chars, index: &i)
                result += convertSuperscript(sup)
            } else if c == "_" {
                // 下标
                i += 1
                let sub = parseArg(chars: chars, index: &i)
                result += convertSubscript(sub)
            } else if c == "$" {
                // 忽略 LaTeX 定界符
                i += 1
            } else {
                result.append(c)
                i += 1
            }
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // 解析 { content } 或 SingleChar
    private static func parseArg(chars: [Character], index: inout Int) -> String {
        if index >= chars.count { return "" }
        if chars[index] == "{" {
            return parseGroup(chars: chars, index: &index)
        } else {
            let c = chars[index]
            index += 1
            return String(c)
        }
    }
    
    // 解析 { ... } 块，处理嵌套
    private static func parseGroup(chars: [Character], index: inout Int) -> String {
        guard index < chars.count, chars[index] == "{" else { return "" }
        index += 1 // skip {
        
        var content = ""
        var depth = 1
        
        let startIndex = index
        
        while index < chars.count {
            if chars[index] == "{" {
                depth += 1
            } else if chars[index] == "}" {
                depth -= 1
                if depth == 0 {
                    // 递归解析内部内容
                    let inner = String(chars[startIndex..<index])
                    index += 1 // skip }
                    // 重要：内部内容可能包含 frac 等命令，需要递归调用 parse
                    // 但为了性能，这里我们简单处理，或者如果需要完美嵌套，应该递归调用 parse
                    return parse(inner)
                }
            }
            index += 1
        }
        return ""
    }
    
    // 基础符号替换
    private static func replaceSymbols(_ text: String) -> String {
        var r = text
        // 希腊字母
        let greeks = [
            "\\alpha": "α", "\\beta": "β", "\\gamma": "γ", "\\delta": "δ", "\\epsilon": "ε",
            "\\theta": "θ", "\\lambda": "λ", "\\mu": "μ", "\\pi": "π", "\\rho": "ρ",
            "\\sigma": "σ", "\\omega": "ω", "\\phi": "φ", "\\psi": "ψ",
            "\\Delta": "Δ", "\\Sigma": "Σ", "\\Omega": "Ω"
        ]
        for (k, v) in greeks { r = r.replacingOccurrences(of: k, with: v) }
        
        // 运算符
        let ops = [
            "\\times": "×", "\\div": "÷", "\\pm": "±", "\\cdot": "·",
            "\\leq": "≤", "\\le": "≤", "\\geq": "≥", "\\ge": "≥",
            "\\neq": "≠", "\\approx": "≈", "\\infty": "∞",
            "\\sum": "∑", "\\int": "∫", "\\partial": "∂", "\\nabla": "∇",
            "\\rightarrow": "→", "\\to": "→", "\\Rightarrow": "⇒",
            "\\leftarrow": "←", "\\uparrow": "↑", "\\downarrow": "↓"
        ]
        for (k, v) in ops { r = r.replacingOccurrences(of: k, with: v) }
        
        return r
    }
    
    private static func convertSuperscript(_ text: String) -> String {
        let map: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
            "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
            "+": "⁺", "-": "⁻", "n": "ⁿ", "x": "ˣ", "y": "ʸ"
        ]
        return String(text.map { map[$0] ?? $0 })
    }
    
    private static func convertSubscript(_ text: String) -> String {
        let map: [Character: Character] = [
            "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
            "5": "₅", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
            "+": "₊", "-": "₋"
        ]
        return String(text.map { map[$0] ?? $0 })
    }
}
