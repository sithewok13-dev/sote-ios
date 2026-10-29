#include "plume_clear.h"

#include <vector>

#include "plume_render_interface.h"
#include "sote_log.h"

namespace plume {
    extern std::unique_ptr<RenderInterface> CreateMetalInterface();
}

namespace sote {
    using namespace plume;

    static const uint32_t BufferCount = 2;
    static const RenderFormat SwapchainFormat = RenderFormat::B8G8R8A8_UNORM;

    class PlumeClearImpl final : public PlumeClear {
        std::unique_ptr<RenderInterface> renderInterface;
        std::unique_ptr<RenderDevice> device;
        std::unique_ptr<RenderCommandQueue> commandQueue;
        std::unique_ptr<RenderCommandList> commandList;
        std::unique_ptr<RenderCommandFence> fence;
        std::unique_ptr<RenderSwapChain> swapChain;
        std::unique_ptr<RenderCommandSemaphore> acquireSemaphore;
        std::vector<std::unique_ptr<RenderCommandSemaphore>> releaseSemaphores;
        std::vector<std::unique_ptr<RenderFramebuffer>> framebuffers;

        void createFramebuffers() {
            framebuffers.clear();
            for (uint32_t i = 0; i < swapChain->getTextureCount(); i++) {
                const RenderTexture *colorAttachment = swapChain->getTexture(i);
                RenderFramebufferDesc fbDesc;
                fbDesc.colorAttachments = &colorAttachment;
                fbDesc.colorAttachmentsCount = 1;
                fbDesc.depthAttachment = nullptr;
                framebuffers.push_back(device->createFramebuffer(fbDesc));
            }
        }

    public:
        uint32_t frameCount = 0;

        bool init(void *window, void *layer) {
            sote::log("plume: CreateMetalInterface");
            renderInterface = CreateMetalInterface();
            if (renderInterface == nullptr) {
                sote::log("plume: CreateMetalInterface failed");
                return false;
            }

            sote::log("plume: createDevice");
            device = renderInterface->createDevice();
            if (device == nullptr) {
                sote::log("plume: createDevice failed");
                return false;
            }

            sote::log("plume: createCommandQueue");
            commandQueue = device->createCommandQueue(RenderCommandListType::DIRECT);
            fence = device->createCommandFence();
            RenderWindow renderWindow = {};
            renderWindow.window = window;
            renderWindow.view = layer;
            sote::log("plume: createSwapChain");
            swapChain = commandQueue->createSwapChain(RenderSwapChainDesc(renderWindow, SwapchainFormat, BufferCount));
            sote::log("plume: swap chain resize");
            if (!swapChain->resize()) {
                sote::log("plume: swap chain resize failed");
                return false;
            }

            sote::log("plume: swap chain %ux%u, %u textures", swapChain->getWidth(), swapChain->getHeight(), swapChain->getTextureCount());
            commandList = commandQueue->createCommandList();
            acquireSemaphore = device->createCommandSemaphore();
            createFramebuffers();
            sote::log("plume: ready");
            return true;
        }

        void resize() override {
            framebuffers.clear();
            if (swapChain->resize()) {
                createFramebuffers();
            }
        }

        void render(float red, float green, float blue) override {
            const uint32_t frame = frameCount++;
            const bool trace = frame < 3;
            if (trace) {
                sote::log("frame %u: begin", frame);
            }

            if (swapChain->needsResize()) {
                resize();
            }

            if (framebuffers.empty()) {
                if (trace) {
                    sote::log("frame %u: no framebuffers", frame);
                }

                return;
            }

            uint32_t imageIndex = 0;
            if (!swapChain->acquireTexture(acquireSemaphore.get(), &imageIndex)) {
                if (trace) {
                    sote::log("frame %u: acquireTexture failed", frame);
                }

                return;
            }

            commandList->begin();
            RenderTexture *swapChainTexture = swapChain->getTexture(imageIndex);
            commandList->barriers(RenderBarrierStage::GRAPHICS, RenderTextureBarrier(swapChainTexture, RenderTextureLayout::COLOR_WRITE));
            commandList->setFramebuffer(framebuffers[imageIndex].get());
            const uint32_t width = swapChain->getWidth();
            const uint32_t height = swapChain->getHeight();
            commandList->setViewports(RenderViewport(0.0f, 0.0f, float(width), float(height)));
            commandList->setScissors(RenderRect(0, 0, width, height));
            commandList->clearColor(0, RenderColor(red, green, blue, 1.0f));
            commandList->barriers(RenderBarrierStage::NONE, RenderTextureBarrier(swapChainTexture, RenderTextureLayout::PRESENT));
            commandList->end();

            while (releaseSemaphores.size() < swapChain->getTextureCount()) {
                releaseSemaphores.emplace_back(device->createCommandSemaphore());
            }

            const RenderCommandList *cmdList = commandList.get();
            RenderCommandSemaphore *waitSemaphore = acquireSemaphore.get();
            RenderCommandSemaphore *signalSemaphore = releaseSemaphores[imageIndex].get();
            commandQueue->executeCommandLists(&cmdList, 1, &waitSemaphore, 1, &signalSemaphore, 1, fence.get());
            swapChain->present(imageIndex, &signalSemaphore, 1);
            commandQueue->waitForCommandFence(fence.get());
            if (trace) {
                sote::log("frame %u: presented", frame);
            }
        }
    };

    std::unique_ptr<PlumeClear> PlumeClear::create(void *window, void *layer) {
        auto clear = std::make_unique<PlumeClearImpl>();
        if (!clear->init(window, layer)) {
            return nullptr;
        }

        return clear;
    }
}
