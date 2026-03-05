"use client"

import React from 'react'
import ReactMarkdown, { Components } from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { KnowledgeBaseReference, KnowledgeBaseActivityRecord } from '@/types/knowledge-retrieval'
import { CitationHoverCard, getDocumentName } from '@/components/citation-hover-card'
import { SourceKindIcon } from '@/components/source-kind-icon'
import { cn } from '@/lib/utils'

interface MarkdownWithCitationsProps {
  text: string
  references?: KnowledgeBaseReference[]
  activity?: KnowledgeBaseActivityRecord[]
  messageId: string | number
  onActivate?: (idx: number, ref?: KnowledgeBaseReference) => void
  className?: string
}

const CITATION_REGEX = /\[ref_id:(\d+)\]/g

/**
 * Renders markdown text with inline citation pills.
 * Citation markers [ref_id:n] are replaced with interactive pills
 * while the rest of the text is rendered as formatted markdown.
 */
export const MarkdownWithCitations: React.FC<MarkdownWithCitationsProps> = ({
  text,
  references = [],
  activity = [],
  messageId,
  onActivate,
  className
}) => {
  // Process a text string to replace [ref_id:n] with citation pill elements
  const processCitations = React.useCallback((textContent: string): React.ReactNode[] => {
    const nodes: React.ReactNode[] = []
    let lastIndex = 0
    let match: RegExpExecArray | null
    const regex = new RegExp(CITATION_REGEX.source, 'g')

    while ((match = regex.exec(textContent)) !== null) {
      if (match.index > lastIndex) {
        nodes.push(textContent.slice(lastIndex, match.index))
      }

      const refIdx = parseInt(match[1], 10)
      const ref = references[refIdx]

      if (ref) {
        const activityEntry = activity.find((a) => a.id === ref.activitySource)
        const documentName = getDocumentName(ref)

        const pill = (
          <button
            key={`cite-${match.index}`}
            type="button"
            onClick={() => {
              if (onActivate) onActivate(refIdx, ref)
              const el = document.getElementById(`ref-${messageId}-${refIdx}`)
              if (el) {
                el.scrollIntoView({ behavior: 'smooth', block: 'center' })
                el.classList.add('ring-2', 'ring-accent', 'ring-offset-1')
                setTimeout(() => el.classList.remove('ring-2', 'ring-accent', 'ring-offset-1'), 1400)
              }
            }}
            aria-label={`View reference: ${documentName}`}
            className={cn(
              "inline-flex items-center gap-1.5 align-baseline",
              "ml-1 px-2 py-0.5 rounded",
              "bg-bg-subtle hover:bg-bg-hover",
              "border border-stroke-divider hover:border-accent/40",
              "text-[11px] text-fg-muted hover:text-fg-default",
              "transition-all duration-150",
              "focus:outline-none focus:ring-1 focus:ring-accent",
              "cursor-pointer"
            )}
          >
            <SourceKindIcon kind={ref.type} size={12} variant="plain" />
            <span className="truncate max-w-[180px]">{documentName}</span>
          </button>
        )

        nodes.push(
          <CitationHoverCard
            key={`hover-${match.index}`}
            reference={ref}
            activity={activityEntry}
            side="top"
            align="center"
          >
            {pill}
          </CitationHoverCard>
        )
      } else {
        nodes.push(
          <span
            key={`cite-${match.index}`}
            className="inline-flex items-center gap-1 ml-1 px-1.5 py-0.5 rounded bg-bg-subtle text-[10px] text-fg-subtle"
          >
            [{refIdx + 1}]
          </span>
        )
      }

      lastIndex = regex.lastIndex
    }

    if (lastIndex < textContent.length) {
      nodes.push(textContent.slice(lastIndex))
    }

    return nodes.length > 0 ? nodes : [textContent]
  }, [references, activity, messageId, onActivate])

  // Custom react-markdown components that process citations within text nodes
  const components: Components = React.useMemo(() => ({
    p: ({ children }) => <p className="mb-2 last:mb-0">{processChildren(children)}</p>,
    li: ({ children }) => <li className="text-sm">{processChildren(children)}</li>,
    strong: ({ children }) => <strong className="font-semibold">{processChildren(children)}</strong>,
    em: ({ children }) => <em>{processChildren(children)}</em>,
    td: ({ children }) => <td className="border border-stroke-divider px-2 py-1">{processChildren(children)}</td>,
    th: ({ children }) => <th className="border border-stroke-divider px-2 py-1 bg-bg-subtle font-medium text-left">{processChildren(children)}</th>,
    // Elements that don't need citation processing
    ul: ({ children }) => <ul className="list-disc ml-4 mb-2 space-y-0.5">{children}</ul>,
    ol: ({ children }) => <ol className="list-decimal ml-4 mb-2 space-y-0.5">{children}</ol>,
    code: ({ children, className: codeClassName }) => {
      const isBlock = codeClassName?.startsWith('language-')
      if (isBlock) {
        return <code className={cn('block bg-bg-subtle rounded-md p-3 my-2 text-xs overflow-x-auto', codeClassName)}>{children}</code>
      }
      return <code className="bg-bg-subtle px-1 py-0.5 rounded text-xs font-mono">{children}</code>
    },
    pre: ({ children }) => <pre className="bg-bg-subtle rounded-md my-2 overflow-x-auto">{children}</pre>,
    h1: ({ children }) => <h3 className="text-base font-semibold mt-3 mb-1">{processChildren(children)}</h3>,
    h2: ({ children }) => <h3 className="text-base font-semibold mt-3 mb-1">{processChildren(children)}</h3>,
    h3: ({ children }) => <h4 className="text-sm font-semibold mt-2 mb-1">{processChildren(children)}</h4>,
    h4: ({ children }) => <h5 className="text-sm font-medium mt-2 mb-1">{processChildren(children)}</h5>,
    table: ({ children }) => (
      <div className="overflow-x-auto my-2">
        <table className="min-w-full text-xs border border-stroke-divider">{children}</table>
      </div>
    ),
    a: ({ href, children }) => (
      <a href={href} target="_blank" rel="noopener noreferrer" className="text-accent hover:underline">{children}</a>
    ),
    blockquote: ({ children }) => (
      <blockquote className="border-l-2 border-accent/40 pl-3 my-2 text-fg-muted italic">{children}</blockquote>
    ),
    hr: () => <hr className="my-3 border-stroke-divider" />,
  }), [processCitations])

  // Recursively process children to find string nodes and inject citations
  function processChildren(children: React.ReactNode): React.ReactNode {
    return React.Children.map(children, (child) => {
      if (typeof child === 'string' && CITATION_REGEX.test(child)) {
        return <>{processCitations(child)}</>
      }
      return child
    })
  }

  return (
    <div className={cn('prose prose-sm dark:prose-invert max-w-none break-words', className)}>
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={components}
    >
      {text}
    </ReactMarkdown>
    </div>
  )
}
