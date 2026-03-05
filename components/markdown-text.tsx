"use client"

import React from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { cn } from '@/lib/utils'

interface MarkdownTextProps {
  content: string
  className?: string
}

/**
 * Renders markdown text with proper formatting (bold, italic, lists, tables, etc.)
 * Uses react-markdown with GFM (GitHub Flavored Markdown) support.
 */
export const MarkdownText: React.FC<MarkdownTextProps> = ({ content, className }) => {
  return (
    <div className={cn('prose prose-sm dark:prose-invert max-w-none break-words', className)}>
    <ReactMarkdown
      remarkPlugins={[remarkGfm]}
      components={{
        // Keep paragraphs inline-friendly for chat bubbles
        p: ({ children }) => <p className="mb-2 last:mb-0">{children}</p>,
        // Style lists
        ul: ({ children }) => <ul className="list-disc ml-4 mb-2 space-y-0.5">{children}</ul>,
        ol: ({ children }) => <ol className="list-decimal ml-4 mb-2 space-y-0.5">{children}</ol>,
        li: ({ children }) => <li className="text-sm">{children}</li>,
        // Bold / italic
        strong: ({ children }) => <strong className="font-semibold">{children}</strong>,
        // Code
        code: ({ children, className: codeClassName }) => {
          const isBlock = codeClassName?.startsWith('language-')
          if (isBlock) {
            return (
              <code className={cn(
                'block bg-bg-subtle rounded-md p-3 my-2 text-xs overflow-x-auto',
                codeClassName
              )}>
                {children}
              </code>
            )
          }
          return (
            <code className="bg-bg-subtle px-1 py-0.5 rounded text-xs font-mono">
              {children}
            </code>
          )
        },
        pre: ({ children }) => <pre className="bg-bg-subtle rounded-md my-2 overflow-x-auto">{children}</pre>,
        // Headings
        h1: ({ children }) => <h3 className="text-base font-semibold mt-3 mb-1">{children}</h3>,
        h2: ({ children }) => <h3 className="text-base font-semibold mt-3 mb-1">{children}</h3>,
        h3: ({ children }) => <h4 className="text-sm font-semibold mt-2 mb-1">{children}</h4>,
        h4: ({ children }) => <h5 className="text-sm font-medium mt-2 mb-1">{children}</h5>,
        // Tables
        table: ({ children }) => (
          <div className="overflow-x-auto my-2">
            <table className="min-w-full text-xs border border-stroke-divider">{children}</table>
          </div>
        ),
        th: ({ children }) => <th className="border border-stroke-divider px-2 py-1 bg-bg-subtle font-medium text-left">{children}</th>,
        td: ({ children }) => <td className="border border-stroke-divider px-2 py-1">{children}</td>,
        // Links
        a: ({ href, children }) => (
          <a href={href} target="_blank" rel="noopener noreferrer" className="text-accent hover:underline">
            {children}
          </a>
        ),
        // Block quotes
        blockquote: ({ children }) => (
          <blockquote className="border-l-2 border-accent/40 pl-3 my-2 text-fg-muted italic">
            {children}
          </blockquote>
        ),
        // Horizontal rule
        hr: () => <hr className="my-3 border-stroke-divider" />,
      }}
    >
      {content}
    </ReactMarkdown>
    </div>
  )
}
