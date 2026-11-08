package main

import (
	"bytes"
	"log"
	"os"

	"github.com/alecthomas/chroma/v2/formatters/html"
	"github.com/alecthomas/chroma/v2/lexers"
	"github.com/alecthomas/chroma/v2/styles"
)

// Copy of GH CSS theme, with stripped out background color and a bit of 
// class compression.
const CSS_GH = `
.chroma .err { color: #a61717; background-color: #e3d2d2 }
.chroma .lnlinks { outline: none; text-decoration: none; color: inherit }
.chroma .lntd { vertical-align: top; padding: 0; margin: 0; border: 0; }
.chroma .lntable { border-spacing: 0; padding: 0; margin: 0; border: 0; }
.chroma .hl { background-color: #e5e5e5 }
.chroma .lnt { white-space: pre; -webkit-user-select: none; user-select: none; margin-right: 0.4em; padding: 0 0.4em 0 0.4em;color: #7f7f7f }
.chroma .ln { white-space: pre; -webkit-user-select: none; user-select: none; margin-right: 0.4em; padding: 0 0.4em 0 0.4em;color: #7f7f7f }
.chroma .line { display: flex; }
.chroma .k,
.chroma .kc,.chroma .kd,
.chroma .kn,.chroma .kp,
.chroma .kr { color: #000000; font-weight: bold }
.chroma .kt { color: #445588; font-weight: bold }
.chroma .na { color: #008080 }
.chroma .nb { color: #0086b3 }
.chroma .bp { color: #999999 }
.chroma .nc { color: #445588; font-weight: bold }
.chroma .no { color: #008080 }
.chroma .nd { color: #3c5d5d; font-weight: bold }
.chroma .ni { color: #800080 }
.chroma .ne,.chroma .nf,
.chroma .nl { color: #990000; font-weight: bold }
.chroma .nn { color: #555555 }
.chroma .nt { color: #000080 }
.chroma .nv { color: #008080 }
.chroma .vc { color: #008080 }
.chroma .vg { color: #008080 }
.chroma .vi { color: #008080 }
.chroma .s,.chroma .sa,
.chroma .sb,.chroma .sc,
.chroma .dl,.chroma .sd,
.chroma .s2,.chroma .se,
.chroma .sh,.chroma .si,
.chroma .sx,.chroma .s1,
.chroma .sr,.chroma .ss { color: #990073 }
.chroma .m,.chroma .mb,
.chroma .mf,.chroma .mh,
.chroma .mi,.chroma .il,
.chroma .mo { color: #009999 }
.chroma .o { color: #000000; font-weight: bold }
.chroma .ow { color: #000000; font-weight: bold }
.chroma .c,.chroma .ch,.chroma .cm,
.chroma .c1 { color: #999988; font-style: italic }
.chroma .cs,.chroma .cp,
.chroma .cpf { color: #999999; font-weight: bold; font-style: italic }
.chroma .gd { color: #000000; background-color: #ffdddd }
.chroma .ge { color: #000000; font-style: italic }
.chroma .gr { color: #aa0000 }
.chroma .gh { color: #999999 }
.chroma .gi { color: #000000; background-color: #ddffdd }
.chroma .go { color: #888888 }
.chroma .gp { color: #555555 }
.chroma .gs { font-weight: bold }
.chroma .gu { color: #aaaaaa }
.chroma .gt { color: #aa0000 }
.chroma .gl { text-decoration: underline }
.chroma .w { color: #bbbbbb }
`

func main() {
	entries, err := os.ReadDir("../template")
	if err != nil {
		log.Fatal("file error: ", err)
	}
	for _, f := range entries {
		if f.IsDir() {
			continue
		}
		x, err := os.ReadFile("../template/" + f.Name())
		if err != nil {
			log.Fatal(err)
		}
		render_template(x, "../blog/"+f.Name())

	}
}

// Renders a template into a full blog post
func render_template(content []byte, target_path string) {
	/* highlighting setup */
	lexer := lexers.Get("text")
	style := styles.Get("github")
	formatter := html.New(html.WithClasses(true))

	result := bytes.NewBufferString("")
	from := 0

	// Find </head> element
	pos := bytes.Index(content[from:], []byte("</head>"))
	if pos == -1 {
		panic("No </head> found!")
	}
	result.Write(content[from:pos])

	// Write CSS classes into head
	result.Write([]byte("<style>\n"))
	// We made some modifications, so don't write raw css
	// formatter.WriteCSS(result, style)
	result.Write([]byte(CSS_GH))
	result.Write([]byte("</style>"))

	from = pos
	// Render code blocks
	for {
		first := bytes.Index(content[from:], []byte("```"))
		if first == -1 {
			break
		}
		// Append non-code blocks to result
		result.Write([]byte(content[from : from+first]))

		from += first + 3

		// Language specifier
		newline := bytes.Index(content[from:], []byte("\n"))
		langspec := bytes.TrimSpace(content[from:from + newline])
		
		if len(langspec) != 0 {
			lexer = lexers.Get(string(bytes.ToLower(langspec)))
		} else {
			lexer = lexers.Get("text")
		}

		// Skip over language specifier
		from += newline + 1

		// Parse closing triple ticks
		second := bytes.Index(content[from:], []byte("```"))
		if second == -1 {
			panic("no matching closing triple tick found")
		}
		// Append code block
		iterator, _ := lexer.Tokenise(nil, string(content[from:from+second]))
		_ = formatter.Format(result, style, iterator)
		from += second + 3
	}
	result.Write(content[from:])

	// Store result in target file
	os.WriteFile(target_path, result.Bytes(), os.ModePerm)
	println(" [x] render: ", target_path)
}
