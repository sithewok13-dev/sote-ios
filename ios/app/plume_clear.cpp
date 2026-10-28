#include "plume_clear.h"

#include <cstdio>
#include <vector>

#include "plume_render_interface.h"

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
        bool init(void *window, void *layer) {
            renderInterface = CreateMetalInterface();
            if (renderInterface == nullptr) {
                fprintf(stderr, "plume: CreateMetalInterface failed\n");
                return false;
            }

            device = renderInterface->createDevice();
            if (device == nullptr) {
                fprintf(stderr, "plume: createDevice failed\n");
                return false;
            }

            commandQueue = device->createCommandQueue(RenderCommandListType::DIRECT);
            fence = device->createCommandFence();
            RenderWindow renderWindow = {};
            renderWindow.window = window;
            renderWindow.view = layer;
            swapChain = commandQueue->createSwapChain(RenderSwapChainDesc(renderWindow, SwapchainFormat, BufferCount));
            if (!swapChain->resize()) {
                fprintf(stderr, "plume: swap chain resize failed\n");
                return false;
            }

            commandList = commandQueue->createCommandList();
            acquireSemaphore = device->createCommandSemaphore();
            createFramebuffers();
            return true;
        }

        void resize() override {
            framebuffers.clear();
            if (swapChain->resize()) {
                createFramebuffers();
            }
        }

        void render(float red, float green, float blue) override {
            if (swapChain->needsResize()) {
                resize();
            }

            if (framebuffers.empty()) {
                return;
            }

            uint32_t imageIndex = 0;
            if (!swapChain->acquireTexture(acquireSemaphore.get(), &imageIndex)) {
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
