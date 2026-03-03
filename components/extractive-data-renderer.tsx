'use client'

import React from 'react'
import { cn } from '@/lib/utils'
import { SourceKindIcon } from '@/components/source-kind-icon'
import { Card, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { 
  DocumentBulletList20Regular, 
  ChevronDown20Regular, 
  ChevronUp20Regular,
  Copy20Regular,
  Checkmark20Regular
} from '@fluentui/react-icons'

/**
 * Represents a single extracted data chunk from Azure AI Search extractive data mode
 * Based on semantic configuration fields: title, content, and keywords
 * Reference: https://learn.microsoft.com/azure/search/agentic-retrieval-how-to-create-knowledge-base
 */
interface ExtractedChunk {
  ref_id: number
  content: string
  title?: string
  /** Keywords/terms from semantic configuration */
  terms?: string
}

interface ExtractiveDataRendererProps {
  /** Raw text that may be JSON extractive data or regular text */
  text: string
  /** References from the API response for linking */
  references?: Array<{
    id: string
    type: string
    docKey?: string
    blobUrl?: string
    sourceData?: any
    rerankerScore?: number
  }>
  /** Callback when a reference is clicked */
  onReferenceClick?: (refId: number) => void
  className?: string
}

/**
 * Attempts to parse text as extractive data JSON array
 * Returns null if not valid extractive data format
 */
function parseExtractiveData(text: string): ExtractedChunk[] | null {
  if (!text) return null
  
  const trimmed = text.trim()
  
  // Must start with [ to be a JSON array
  if (!trimmed.startsWith('[')) return null
  
  try {
    const parsed = JSON.parse(trimmed)
    
    // Validate it's an array with extractive data structure
    if (!Array.isArray(parsed) || parsed.length === 0) return null
    
    // Check if first item has expected structure
    const first = parsed[0]
    if (typeof first !== 'object' || !('ref_id' in first) || !('content' in first)) {
      return null
    }
    
    return parsed as ExtractedChunk[]
  } catch {
    return null
  }
}

/**
 * Format content text with better structure:
 * - Detect and format section headers
 * - Handle newlines properly
 * - Clean up whitespace
 * - Handle tables and structured data
 */
function formatContent(content: string, isExpanded: boolean = true): React.ReactNode[] {
  if (!content) return []
  
  // Maximum chars to show when collapsed
  const MAX_COLLAPSED_CHARS = 400
  
  let displayContent = content
  if (!isExpanded && content.length > MAX_COLLAPSED_CHARS) {
    displayContent = content.slice(0, MAX_COLLAPSED_CHARS)
  }
  
  const lines = displayContent.split('\n')
  const nodes: React.ReactNode[] = []
  let currentParagraph: string[] = []
  let inTable = false
  let tableRows: string[][] = []
  
  const flushParagraph = () => {
    if (currentParagraph.length > 0) {
      nodes.push(
        <p key={`p-${nodes.length}`} className="text-sm text-fg-default leading-relaxed mb-2">
          {currentParagraph.join(' ')}
        </p>
      )
      currentParagraph = []
    }
  }
  
  const flushTable = () => {
    if (tableRows.length > 0) {
      nodes.push(
        <div key={`table-${nodes.length}`} className="overflow-x-auto mb-3 -mx-2">
          <table className="w-full text-xs border-collapse">
            <tbody>
              {tableRows.map((row, rowIdx) => (
                <tr key={rowIdx} className={rowIdx === 0 ? 'bg-bg-subtle font-medium' : 'border-t border-stroke-divider'}>
                  {row.map((cell, cellIdx) => (
                    <td key={cellIdx} className="px-2 py-1.5 text-left align-top">
                      {cell.trim()}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )
      tableRows = []
      inTable = false
    }
  }
  
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim()
    
    // Skip empty lines but flush paragraph
    if (!line) {
      flushParagraph()
      flushTable()
      continue
    }
    
    // Detect table rows (lines with multiple spaces/tabs suggesting columnar data)
    const isTableRow = /\s{2,}/.test(line) && /\d+/.test(line) && /%/.test(line)
    if (isTableRow) {
      flushParagraph()
      inTable = true
      // Split by multiple spaces
      const cells = line.split(/\s{2,}/).filter(Boolean)
      tableRows.push(cells)
      continue
    } else if (inTable) {
      flushTable()
    }
    
    // Detect section headers (ALL CAPS followed by text, or ending with specific patterns)
    const isHeader = /^[A-Z][A-Z\s&\/\-]+$/.test(line) && line.length < 50
    const isSubHeader = /^[A-Z][a-z]+(\s[A-Z][a-z]+)*$/.test(line) && line.length < 40 && !line.includes('.')
    
    // Detect bullet points
    const isBullet = /^[\-\•\*]\s/.test(line) || /^\d+\.\s/.test(line)
    
    if (isHeader) {
      flushParagraph()
      nodes.push(
        <h4 key={`h-${nodes.length}`} className="text-sm font-semibold text-fg-default mt-3 mb-1.5 first:mt-0 border-b border-stroke-divider/50 pb-1">
          {line}
        </h4>
      )
    } else if (isSubHeader && i < lines.length - 1) {
      flushParagraph()
      nodes.push(
        <h5 key={`h5-${nodes.length}`} className="text-sm font-medium text-fg-muted mt-2 mb-1">
          {line}
        </h5>
      )
    } else if (isBullet) {
      flushParagraph()
      nodes.push(
        <div key={`bullet-${nodes.length}`} className="flex gap-2 text-sm text-fg-default mb-1 pl-2">
          <span className="text-fg-muted">•</span>
          <span>{line.replace(/^[\-\•\*\d\.]\s*/, '')}</span>
        </div>
      )
    } else {
      // Regular text - add to current paragraph
      currentParagraph.push(line)
    }
  }
  
  // Flush any remaining content
  flushParagraph()
  flushTable()
  
  // Add ellipsis indicator if truncated
  if (!isExpanded && content.length > MAX_COLLAPSED_CHARS) {
    nodes.push(
      <span key="ellipsis" className="text-fg-muted">...</span>
    )
  }
  
  return nodes
}

/**
 * Get a display title for a chunk, trying various sources
 */
function getChunkTitle(chunk: ExtractedChunk, reference?: any): string {
  // Try chunk title first
  if (chunk.title) return chunk.title
  
  // Try reference sourceData
  if (reference?.sourceData?.title) return reference.sourceData.title
  
  // Try to extract from docKey/blobUrl
  if (reference?.docKey) {
    const fileName = reference.docKey.split('/').pop() || reference.docKey
    return fileName.replace(/\.[^/.]+$/, '') // Remove extension
  }
  
  if (reference?.blobUrl) {
    try {
      const url = new URL(reference.blobUrl)
      const fileName = url.pathname.split('/').pop() || 'Document'
      return decodeURIComponent(fileName.replace(/\.[^/.]+$/, ''))
    } catch {
      // Fallback
    }
  }
  
  // Try to detect title from content (first short line that looks like a title)
  const firstLine = chunk.content?.split('\n')[0]?.trim()
  if (firstLine && firstLine.length < 60 && !firstLine.includes('.')) {
    return firstLine
  }
  
  return `Source ${chunk.ref_id + 1}`
}

/**
 * Individual chunk card with expand/collapse and copy functionality
 */
function ChunkCard({ 
  chunk, 
  reference,
  onReferenceClick 
}: { 
  chunk: ExtractedChunk
  reference?: ExtractiveDataRendererProps['references'][0]
  onReferenceClick?: (refId: number) => void
}) {
  const [isExpanded, setIsExpanded] = React.useState(false)
  const [copied, setCopied] = React.useState(false)
  
  const title = getChunkTitle(chunk, reference)
  const sourceType = reference?.type || 'searchIndex'
  const isLongContent = chunk.content.length > 400
  
  const handleCopy = async (e: React.MouseEvent) => {
    e.stopPropagation()
    try {
      await navigator.clipboard.writeText(chunk.content)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch (err) {
      console.error('Failed to copy:', err)
    }
  }
  
  const handleExpand = (e: React.MouseEvent) => {
    e.stopPropagation()
    setIsExpanded(!isExpanded)
  }
  
  return (
    <Card 
      className={cn(
        'bg-bg-subtle border border-stroke-divider',
        'hover:border-accent/40 transition-colors'
      )}
    >
      <CardContent className="p-4">
        {/* Source header */}
        <div className="flex items-start gap-2 mb-3">
          <div className="flex-shrink-0 mt-0.5">
            <SourceKindIcon kind={sourceType} size={16} variant="badge" />
          </div>
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 
                className={cn(
                  "text-sm font-medium text-fg-default truncate",
                  onReferenceClick && "cursor-pointer hover:text-accent"
                )}
                onClick={() => onReferenceClick?.(chunk.ref_id)}
              >
                {title}
              </h3>
              <span className="flex-shrink-0 text-[10px] text-fg-subtle bg-bg-card px-1.5 py-0.5 rounded">
                [{chunk.ref_id + 1}]
              </span>
            </div>
            <div className="flex items-center gap-2 mt-0.5">
              {reference?.rerankerScore && (
                <span className="text-[10px] text-fg-muted">
                  Relevance: {(reference.rerankerScore * 100).toFixed(0)}%
                </span>
              )}
              {chunk.terms && (
                <span className="text-[10px] text-accent bg-accent/10 px-1.5 py-0.5 rounded">
                  {chunk.terms.split(',').slice(0, 3).join(', ')}
                </span>
              )}
            </div>
          </div>
          
          {/* Action buttons */}
          <div className="flex items-center gap-1">
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={handleCopy}
              title="Copy content"
            >
              {copied ? (
                <Checkmark20Regular className="h-3.5 w-3.5 text-green-600" />
              ) : (
                <Copy20Regular className="h-3.5 w-3.5" />
              )}
            </Button>
            {isLongContent && (
              <Button
                variant="ghost"
                size="icon"
                className="h-6 w-6"
                onClick={handleExpand}
                title={isExpanded ? "Collapse" : "Expand"}
              >
                {isExpanded ? (
                  <ChevronUp20Regular className="h-3.5 w-3.5" />
                ) : (
                  <ChevronDown20Regular className="h-3.5 w-3.5" />
                )}
              </Button>
            )}
          </div>
        </div>
        
        {/* Content */}
        <div className={cn(
          "prose prose-sm max-w-none",
          !isExpanded && isLongContent && "max-h-[200px] overflow-hidden relative"
        )}>
          {formatContent(chunk.content, isExpanded || !isLongContent)}
          
          {/* Fade overlay for collapsed content */}
          {!isExpanded && isLongContent && (
            <div className="absolute bottom-0 left-0 right-0 h-12 bg-gradient-to-t from-bg-subtle to-transparent" />
          )}
        </div>
        
        {/* Show more button for collapsed content */}
        {!isExpanded && isLongContent && (
          <button
            onClick={handleExpand}
            className="mt-2 text-xs text-accent hover:text-accent/80 font-medium"
          >
            Show more ({Math.ceil(chunk.content.length / 100)}+ lines)
          </button>
        )}
      </CardContent>
    </Card>
  )
}

/**
 * ExtractiveDataRenderer
 * 
 * Detects if response text is extractive data format (JSON array with ref_id/content)
 * and renders it as nicely formatted cards. Falls back to rendering plain text.
 * 
 * Reference: https://learn.microsoft.com/azure/search/agentic-retrieval-how-to-create-knowledge-base
 */
export const ExtractiveDataRenderer: React.FC<ExtractiveDataRendererProps> = ({
  text,
  references = [],
  onReferenceClick,
  className
}) => {
  const extractedData = React.useMemo(() => parseExtractiveData(text), [text])
  
  // Not extractive data - return null to indicate fallback rendering should be used
  if (!extractedData) {
    return null
  }
  
  // Render extractive data as a list of source cards
  return (
    <div className={cn('space-y-4', className)}>
      {/* Header indicator */}
      <div className="flex items-center gap-2 text-xs text-fg-muted">
        <DocumentBulletList20Regular className="h-4 w-4" />
        <span>Extracted from {extractedData.length} source{extractedData.length !== 1 ? 's' : ''}</span>
      </div>
      
      {/* Source cards */}
      <div className="space-y-3">
        {extractedData.map((chunk, index) => {
          // Find matching reference
          const reference = references.find(r => r.id === String(chunk.ref_id)) || references[chunk.ref_id]
          
          return (
            <ChunkCard
              key={`chunk-${chunk.ref_id}-${index}`}
              chunk={chunk}
              reference={reference}
              onReferenceClick={onReferenceClick}
            />
          )
        })}
      </div>
    </div>
  )
}

/**
 * Hook to check if text is extractive data format
 */
export function useIsExtractiveData(text: string): boolean {
  return React.useMemo(() => parseExtractiveData(text) !== null, [text])
}

export { parseExtractiveData }
