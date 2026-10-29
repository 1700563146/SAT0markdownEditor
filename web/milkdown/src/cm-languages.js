// 精选 CodeMirror 语言注册表，替代 @codemirror/language-data 的全量注册表。
//
// 全量注册表会静态引入 @codemirror/legacy-modes（~800KB）与 20 多个 lang-* /
// @lezer/* 语法包（cpp/php/rust/sql/liquid/jinja/vue…），是 bundle 体积与
// “打开文档”时 JS 解析/求值耗时的最大单一来源。这里只保留常用语言：
// 预览态的代码高亮仍由 refractor（覆盖面更广）负责，CodeMirror 语法只在
// 进入代码块编辑态时生效。
import { LanguageDescription } from '@codemirror/language';
import { javascript } from '@codemirror/lang-javascript';
import { html } from '@codemirror/lang-html';
import { css } from '@codemirror/lang-css';
import { json } from '@codemirror/lang-json';
import { yaml } from '@codemirror/lang-yaml';
import { xml } from '@codemirror/lang-xml';
import { python } from '@codemirror/lang-python';
import { markdown } from '@codemirror/lang-markdown';
import { sql } from '@codemirror/lang-sql';
import { java } from '@codemirror/lang-java';
import { cpp } from '@codemirror/lang-cpp';
import { rust } from '@codemirror/lang-rust';
import { go } from '@codemirror/lang-go';

// LanguageDescription.load 必须返回 Promise<LanguageSupport>，同步返回扩展会被
// CodeMirror 当成 thenable 之外的对象并抛 "loadFunc(...).then is not a function"。
const of = (name, extensions, alias, load) =>
  LanguageDescription.of({
    name,
    extensions,
    alias,
    load: async () => load(),
  });

export const languages = [
  of('JavaScript', ['js', 'mjs', 'cjs'], ['js', 'jsx'], () => javascript({ jsx: true })),
  of('TypeScript', ['ts', 'tsx'], ['ts'], () => javascript({ jsx: true, typescript: true })),
  of('HTML', ['html', 'htm'], [], () => html()),
  of('CSS', ['css'], ['less'], () => css()),
  of('JSON', ['json', 'jsonc'], [], () => json()),
  of('YAML', ['yaml', 'yml'], [], () => yaml()),
  of('XML', ['xml', 'svg'], [], () => xml()),
  of('Python', ['py', 'python'], [], () => python()),
  of('Markdown', ['md', 'markdown'], [], () => markdown()),
  of('SQL', ['sql'], [], () => sql()),
  of('Java', ['java'], [], () => java()),
  of('C++', ['cpp', 'cc', 'hpp'], ['c', 'cxx'], () => cpp()),
  of('Rust', ['rs', 'rust'], [], () => rust()),
  of('Go', ['go'], [], () => go()),
];

export default languages;
