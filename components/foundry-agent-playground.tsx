'use client'

import { useState, useRef, useEffect, useCallback } from 'react'
import { 
  Send20Regular, 
  Bot20Regular, 
  Person20Regular, 
  ArrowCounterclockwise20Regular,
  Wrench20Regular,
  BrainCircuit20Regular,
  Info20Regular,
  Dismiss20Regular
} from '@fluentui/react-icons'
import { motion, AnimatePresence } from 'framer-motion'
import { Button } from '@/components/ui/button'
import { Textarea } from '@/components/ui/textarea'
import { Card, CardContent } from '@/components/ui/card'
import { Badge } from '@/components/ui/badge'
import { LoadingSkeleton } from '@/components/shared/loading-skeleton'
import { cn } from '@/lib/utils'

// --- Types ---

type FoundryAgent = {
  id: string
  name: string
  model: string
  instructions?: string
  tools?: Array<{
    type: string
    server_label?: string
    server_url?: string
    allowed_tools?: string[]
    project_connection_id?: string
  }>
}

type ToolCall = {
  id: string
  type: string
  name?: string
  arguments?: string
  server_label?: string
}

type ToolResult = {
  call_id: string
  output?: string
}

type OutputItem = {
  type: string
  id?: string
  role?: string
  content?: Array<{ type: string; text?: string; annotations?: unknown[] }>
  status?: string
  name?: string
  arguments?: string
  call_id?: string
  output?: string
  server_label?: string
}

type ResponseData = {
  id: string
  output?: OutputItem[]
  usage?: {
    input_tokens: number
    output_tokens: number
    total_tokens: number
  }
  error?: { message: string }
}

type ChatMessage = {
  id: string
  role: 'user' | 'assistant'
  content: string
  timestamp: Date
  toolCalls?: ToolCall[]
  toolResults?: ToolResult[]
  usage?: ResponseData['usage']
  responseId?: string
}

// --- Conversation Starters ---

const STARTER_QUESTIONS = [
  { label: '🏭 Manufacturing', question: 'What are the main challenges in modern manufacturing quality control?' },
  { label: '🏥 Healthcare', question: 'What are the key considerations for healthcare data management?' },
  { label: '💰 Financial', question: 'What are the best practices for financial risk assessment?' },
  { label: '🔍 Cross-domain', question: 'Compare the approaches to compliance across manufacturing, healthcare, and financial sectors.' },
]

// --- Component ---

export function FoundryAgentPlayground() {
  const [agents, setAgents] = useState<FoundryAgent[]>([])
  const [selectedAgent, setSelectedAgent] = useState<FoundryAgent | null>(null)
  const [agentsLoading, setAgentsLoading] = useState(true)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [isLoading, setIsLoading] = useState(false)
  const [previousResponseId, setPreviousResponseId] = useState<string | null>(null)
  const [showAgentInfo, setShowAgentInfo] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const messagesEndRef = useRef<HTMLDivElement>(null)
  const textareaRef = useRef<HTMLTextAreaElement>(null)

  // Scroll to bottom on new messages
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages])

  // Load agents on mount
  useEffect(() => {
    loadAgents()
  }, [])

  const loadAgents = async () => {
    try {
      setAgentsLoading(true)
      const res = await fetch('/api/agentsv2/agents')
      if (!res.ok) {
        const err = await res.json()
        setError(err.details || err.error || 'Failed to load agents')
        return
      }
      const data = await res.json()
      // The response is { data: [...] } with nested versions.latest.definition
      const rawList = data.data || data.value || (Array.isArray(data) ? data : [])
      const agentList: FoundryAgent[] = rawList.map((a: Record<string, unknown>) => {
        const def = (a.versions as Record<string, Record<string, Record<string, unknown>>>)?.latest?.definition
        return {
          id: a.id as string,
          name: a.name as string,
          model: (def?.model as string) || '',
          instructions: (def?.instructions as string) || '',
          tools: (def?.tools as FoundryAgent['tools']) || [],
        }
      })
      setAgents(agentList)
      // Auto-select foundry-iq-agent if available
      const defaultAgent = agentList.find(a => a.name === 'foundry-iq-agent') || agentList[0]
      if (defaultAgent) {
        setSelectedAgent(defaultAgent)
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Failed to load agents')
    } finally {
      setAgentsLoading(false)
    }
  }

  const sendMessage = useCallback(async (messageText?: string) => {
    const text = messageText || input.trim()
    if (!text || isLoading || !selectedAgent) return

    setInput('')
    setError(null)

    const userMsg: ChatMessage = {
      id: `user-${Date.now()}`,
      role: 'user',
      content: text,
      timestamp: new Date(),
    }

    setMessages(prev => [...prev, userMsg])
    setIsLoading(true)

    try {
      const res = await fetch('/api/agentsv2/responses', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          input: text,
          agent_name: selectedAgent.name,
          ...(previousResponseId && { previous_response_id: previousResponseId }),
        }),
      })

      if (!res.ok) {
        const err = await res.json()
        throw new Error(err.details || err.error || `HTTP ${res.status}`)
      }

      const data: ResponseData = await res.json()

      // Parse the response output
      const toolCalls: ToolCall[] = []
      const toolResults: ToolResult[] = []
      let assistantText = ''

      if (data.output) {
        for (const item of data.output) {
          if (item.type === 'mcp_call' || item.type === 'function_call') {
            toolCalls.push({
              id: item.id || '',
              type: item.type,
              name: item.name,
              arguments: item.arguments,
              server_label: item.server_label,
            })
          } else if (item.type === 'mcp_call_output' || item.type === 'function_call_output') {
            toolResults.push({
              call_id: item.call_id || '',
              output: item.output,
            })
          } else if (item.type === 'message' && item.role === 'assistant') {
            if (item.content) {
              for (const c of item.content) {
                if (c.type === 'output_text' || c.type === 'text') {
                  assistantText += c.text || ''
                }
              }
            }
          }
        }
      }

      const assistantMsg: ChatMessage = {
        id: `assistant-${Date.now()}`,
        role: 'assistant',
        content: assistantText || 'No response content.',
        timestamp: new Date(),
        toolCalls: toolCalls.length > 0 ? toolCalls : undefined,
        toolResults: toolResults.length > 0 ? toolResults : undefined,
        usage: data.usage,
        responseId: data.id,
      }

      setMessages(prev => [...prev, assistantMsg])
      setPreviousResponseId(data.id)
    } catch (err) {
      const errorMsg: ChatMessage = {
        id: `error-${Date.now()}`,
        role: 'assistant',
        content: `Error: ${err instanceof Error ? err.message : 'Unknown error'}`,
        timestamp: new Date(),
      }
      setMessages(prev => [...prev, errorMsg])
    } finally {
      setIsLoading(false)
    }
  }, [input, isLoading, selectedAgent, previousResponseId])

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      sendMessage()
    }
  }

  const resetConversation = () => {
    setMessages([])
    setPreviousResponseId(null)
    setError(null)
  }

  // --- Loading state ---
  if (agentsLoading) {
    return (
      <div className="h-[calc(100vh-7rem)] flex flex-col items-center justify-center gap-4">
        <LoadingSkeleton className="h-8 w-64" />
        <LoadingSkeleton className="h-4 w-48" />
        <p className="text-fg-muted text-sm">Loading Foundry agents...</p>
      </div>
    )
  }

  // --- No agents state ---
  if (!selectedAgent) {
    return (
      <div className="h-[calc(100vh-7rem)] flex items-center justify-center">
        <Card className="w-full max-w-md">
          <CardContent className="pt-8 pb-8 text-center space-y-4">
            <Bot20Regular className="w-12 h-12 text-fg-muted mx-auto" />
            <h3 className="text-lg font-semibold">No Agents Found</h3>
            <p className="text-fg-muted text-sm">
              {error || 'No Foundry agents are deployed. Run `azd up` to provision the foundry-iq-agent.'}
            </p>
            <Button variant="outline" onClick={loadAgents}>
              Retry
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  // --- Main chat UI ---
  return (
    <div className="h-[calc(100vh-7rem)] flex flex-col">
      {/* Header */}
      <div className="border-b border-stroke-divider px-6 py-4 flex items-center justify-between bg-bg-surface/50">
        <div className="flex items-center gap-3">
          <div className="w-10 h-10 rounded-full bg-gradient-to-br from-purple-500 to-indigo-600 flex items-center justify-center">
            <BrainCircuit20Regular className="w-5 h-5 text-white" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h2 className="font-semibold text-fg-default">{selectedAgent.name}</h2>
              <Badge variant="outline" className="text-xs">Foundry Agent</Badge>
            </div>
            <p className="text-xs text-fg-muted">
              Model: {selectedAgent.model} · {selectedAgent.tools?.length || 0} tool(s) configured
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {agents.length > 1 && (
            <select 
              className="text-sm border border-stroke-divider rounded-md px-2 py-1 bg-bg-surface"
              value={selectedAgent.id}
              onChange={(e) => {
                const agent = agents.find(a => a.id === e.target.value)
                if (agent) {
                  setSelectedAgent(agent)
                  resetConversation()
                }
              }}
            >
              {agents.map(a => (
                <option key={a.id} value={a.id}>{a.name}</option>
              ))}
            </select>
          )}
          <Button 
            variant="ghost" 
            size="sm"
            onClick={() => setShowAgentInfo(!showAgentInfo)}
            title="Agent info"
          >
            <Info20Regular />
          </Button>
          <Button variant="ghost" size="sm" onClick={resetConversation} title="Reset conversation">
            <ArrowCounterclockwise20Regular />
          </Button>
        </div>
      </div>

      <div className="flex-1 flex overflow-hidden">
        {/* Chat area */}
        <div className="flex-1 flex flex-col">
          {/* Messages */}
          <div className="flex-1 overflow-y-auto px-6 py-4 space-y-4">
            {messages.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full gap-6">
                <motion.div
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="text-center space-y-3"
                >
                  <div className="w-16 h-16 rounded-full bg-gradient-to-br from-purple-500/20 to-indigo-600/20 flex items-center justify-center mx-auto">
                    <BrainCircuit20Regular className="w-8 h-8 text-purple-500" />
                  </div>
                  <h3 className="text-lg font-semibold text-fg-default">Foundry Agent Playground</h3>
                  <p className="text-fg-muted text-sm max-w-md">
                    Chat with a Foundry Agent that uses MCP tools to retrieve knowledge from Azure AI Search. 
                    Unlike direct KB queries, the agent reasons about your question and uses tools autonomously.
                  </p>
                </motion.div>
                <div className="grid grid-cols-2 gap-3 max-w-lg w-full">
                  {STARTER_QUESTIONS.map((starter, i) => (
                    <motion.button
                      key={i}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      transition={{ delay: 0.1 * i }}
                      className="text-left p-3 rounded-lg border border-stroke-divider hover:border-purple-500/50 
                                 hover:bg-purple-500/5 transition-all text-sm group"
                      onClick={() => sendMessage(starter.question)}
                    >
                      <span className="text-xs text-fg-muted group-hover:text-purple-500">{starter.label}</span>
                      <p className="text-fg-default mt-1 line-clamp-2">{starter.question}</p>
                    </motion.button>
                  ))}
                </div>
              </div>
            ) : (
              <>
                {messages.map((msg) => (
                  <MessageBubble key={msg.id} message={msg} />
                ))}
                {isLoading && (
                  <motion.div
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    className="flex gap-3 items-start"
                  >
                    <div className="w-8 h-8 rounded-full bg-gradient-to-br from-purple-500 to-indigo-600 flex items-center justify-center flex-shrink-0">
                      <BrainCircuit20Regular className="w-4 h-4 text-white" />
                    </div>
                    <div className="flex items-center gap-2 text-fg-muted text-sm py-2">
                      <div className="flex gap-1">
                        <span className="w-2 h-2 rounded-full bg-purple-500 animate-bounce" style={{ animationDelay: '0ms' }} />
                        <span className="w-2 h-2 rounded-full bg-purple-500 animate-bounce" style={{ animationDelay: '150ms' }} />
                        <span className="w-2 h-2 rounded-full bg-purple-500 animate-bounce" style={{ animationDelay: '300ms' }} />
                      </div>
                      <span>Agent is thinking...</span>
                    </div>
                  </motion.div>
                )}
                <div ref={messagesEndRef} />
              </>
            )}
          </div>

          {/* Input area */}
          <div className="border-t border-stroke-divider p-4 bg-bg-surface/50">
            <div className="flex gap-3 items-end max-w-4xl mx-auto">
              <Textarea
                ref={textareaRef}
                value={input}
                onChange={(e) => setInput(e.target.value)}
                onKeyDown={handleKeyDown}
                placeholder={`Ask ${selectedAgent.name} a question...`}
                className="min-h-[44px] max-h-[200px] resize-none"
                rows={1}
                disabled={isLoading}
              />
              <Button
                onClick={() => sendMessage()}
                disabled={!input.trim() || isLoading}
                className="bg-purple-600 hover:bg-purple-700 text-white flex-shrink-0"
              >
                <Send20Regular />
              </Button>
            </div>
            <p className="text-xs text-fg-muted text-center mt-2">
              Foundry Agent uses MCP tools to query Azure AI Search knowledge bases
            </p>
          </div>
        </div>

        {/* Agent Info Panel */}
        <AnimatePresence>
          {showAgentInfo && (
            <motion.div
              initial={{ width: 0, opacity: 0 }}
              animate={{ width: 360, opacity: 1 }}
              exit={{ width: 0, opacity: 0 }}
              transition={{ duration: 0.2 }}
              className="border-l border-stroke-divider overflow-hidden"
            >
              <div className="w-[360px] h-full overflow-y-auto p-4 space-y-4">
                <div className="flex items-center justify-between">
                  <h3 className="font-semibold text-fg-default">Agent Details</h3>
                  <Button variant="ghost" size="sm" onClick={() => setShowAgentInfo(false)}>
                    <Dismiss20Regular />
                  </Button>
                </div>

                <div className="space-y-3">
                  <InfoRow label="Name" value={selectedAgent.name} />
                  <InfoRow label="Model" value={selectedAgent.model} />
                  <InfoRow label="ID" value={selectedAgent.id} mono />

                  {selectedAgent.instructions && (
                    <div>
                      <p className="text-xs font-medium text-fg-muted mb-1">Instructions</p>
                      <p className="text-sm text-fg-default bg-bg-subtle rounded-md p-2 whitespace-pre-wrap">
                        {selectedAgent.instructions}
                      </p>
                    </div>
                  )}

                  {selectedAgent.tools && selectedAgent.tools.length > 0 && (
                    <div>
                      <p className="text-xs font-medium text-fg-muted mb-2">Tools</p>
                      <div className="space-y-2">
                        {selectedAgent.tools.map((tool, i) => (
                          <div key={i} className="bg-bg-subtle rounded-md p-3 space-y-1.5">
                            <div className="flex items-center gap-2">
                              <Wrench20Regular className="w-4 h-4 text-purple-500" />
                              <span className="text-sm font-medium">{tool.server_label || tool.type}</span>
                              <Badge variant="outline" className="text-xs">{tool.type}</Badge>
                            </div>
                            {tool.server_url && (
                              <p className="text-xs text-fg-muted break-all font-mono">
                                {tool.server_url}
                              </p>
                            )}
                            {tool.allowed_tools && (
                              <div className="flex gap-1 flex-wrap">
                                {tool.allowed_tools.map(t => (
                                  <Badge key={t} variant="secondary" className="text-xs">{t}</Badge>
                                ))}
                              </div>
                            )}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}
                </div>

                {/* Differentiation info */}
                <div className="border-t border-stroke-divider pt-3">
                  <p className="text-xs font-medium text-fg-muted mb-2">How is this different from KB Playground?</p>
                  <div className="text-xs text-fg-muted space-y-2">
                    <p>
                      <strong className="text-fg-default">KB Playground</strong> sends queries directly to Azure AI Search 
                      Knowledge Bases — a single retrieve-and-answer call.
                    </p>
                    <p>
                      <strong className="text-fg-default">Agent Playground</strong> uses Azure AI Foundry&apos;s Agent Service. 
                      The agent reasons about your question, decides which tools to call (MCP), interprets 
                      results, and can do multi-step retrieval across knowledge bases.
                    </p>
                  </div>
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  )
}

// --- Sub-components ---

function InfoRow({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div>
      <p className="text-xs font-medium text-fg-muted">{label}</p>
      <p className={cn('text-sm text-fg-default', mono && 'font-mono text-xs break-all')}>{value}</p>
    </div>
  )
}

function MessageBubble({ message }: { message: ChatMessage }) {
  const isUser = message.role === 'user'
  const [showToolDetails, setShowToolDetails] = useState(false)

  return (
    <motion.div
      initial={{ opacity: 0, y: 8 }}
      animate={{ opacity: 1, y: 0 }}
      className={cn('flex gap-3 items-start', isUser && 'flex-row-reverse')}
    >
      {/* Avatar */}
      <div className={cn(
        'w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0',
        isUser 
          ? 'bg-blue-500/10 text-blue-500' 
          : 'bg-gradient-to-br from-purple-500 to-indigo-600'
      )}>
        {isUser ? (
          <Person20Regular className="w-4 h-4" />
        ) : (
          <BrainCircuit20Regular className="w-4 h-4 text-white" />
        )}
      </div>

      {/* Content */}
      <div className={cn('max-w-[75%] space-y-2', isUser && 'items-end')}>
        <div className={cn(
          'rounded-xl px-4 py-2.5 text-sm',
          isUser
            ? 'bg-blue-500 text-white rounded-tr-sm'
            : 'bg-bg-subtle text-fg-default rounded-tl-sm'
        )}>
          <p className="whitespace-pre-wrap">{message.content}</p>
        </div>

        {/* Tool calls indicator */}
        {message.toolCalls && message.toolCalls.length > 0 && (
          <button
            onClick={() => setShowToolDetails(!showToolDetails)}
            className="flex items-center gap-1.5 text-xs text-purple-500 hover:text-purple-600 transition-colors"
          >
            <Wrench20Regular className="w-3.5 h-3.5" />
            <span>{message.toolCalls.length} tool call(s)</span>
            <span className="text-fg-muted">{showToolDetails ? '▲' : '▼'}</span>
          </button>
        )}

        {/* Tool call details */}
        <AnimatePresence>
          {showToolDetails && message.toolCalls && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: 'auto', opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              className="overflow-hidden space-y-2"
            >
              {message.toolCalls.map((tc) => {
                const result = message.toolResults?.find(r => r.call_id === tc.id)
                return (
                  <div key={tc.id} className="bg-purple-500/5 border border-purple-500/20 rounded-lg p-3 text-xs space-y-1.5">
                    <div className="flex items-center gap-2">
                      <Wrench20Regular className="w-3.5 h-3.5 text-purple-500" />
                      <span className="font-medium text-purple-600">{tc.name || tc.type}</span>
                      {tc.server_label && (
                        <Badge variant="outline" className="text-xs">{tc.server_label}</Badge>
                      )}
                    </div>
                    {tc.arguments && (
                      <details className="group">
                        <summary className="cursor-pointer text-fg-muted hover:text-fg-default">Arguments</summary>
                        <pre className="mt-1 p-2 bg-bg-subtle rounded text-xs overflow-x-auto font-mono max-h-32 overflow-y-auto">
                          {formatJson(tc.arguments)}
                        </pre>
                      </details>
                    )}
                    {result?.output && (
                      <details className="group">
                        <summary className="cursor-pointer text-fg-muted hover:text-fg-default">Result</summary>
                        <pre className="mt-1 p-2 bg-bg-subtle rounded text-xs overflow-x-auto font-mono max-h-48 overflow-y-auto">
                          {formatJson(result.output)}
                        </pre>
                      </details>
                    )}
                  </div>
                )
              })}
            </motion.div>
          )}
        </AnimatePresence>

        {/* Usage stats */}
        {message.usage && (
          <p className="text-xs text-fg-muted">
            Tokens: {message.usage.input_tokens} in / {message.usage.output_tokens} out
          </p>
        )}
      </div>
    </motion.div>
  )
}

function formatJson(str: string): string {
  try {
    return JSON.stringify(JSON.parse(str), null, 2)
  } catch {
    return str
  }
}
